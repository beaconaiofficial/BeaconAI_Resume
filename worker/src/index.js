// beaconai-resume-proxy (Cloudflare Worker) — BeaconAI Resume's AI proxy.
//
// The app never talks to api.anthropic.com directly (the API key would ship
// in the APK). It posts Anthropic-shaped Messages requests here; this Worker
// checks them and forwards them with the key held as a Worker secret.
//
// Why this exists separately: Resume used to share the `beaconai-proxy`
// Worker with BeaconAI Tools. A Tools deploy on 2026-10-28 replaced that
// script and Resume's route disappeared (every call → 404 not_found).
// Resume now has its own Worker; `beaconai-proxy` forwards path "/" here via
// a service binding so installs that still use the old URL keep working.
//
// Request (what every Resume version sends)
//   POST /   headers: Content-Type: application/json, X-BeaconAI-Secret
//   body:    {model, max_tokens, system?, messages, tools?}
//
// Checks: shared secret, model allowlist, max_tokens cap, tool allowlist,
// body size, daily quotas (per IP and global) in KV. Unknown top-level body
// fields are dropped rather than forwarded.
//
// Bindings (wrangler.toml): RATE_LIMIT (KV), ANTHROPIC_API_KEY and
// APP_SHARED_SECRET (secrets), PER_IP_DAILY and GLOBAL_DAILY (vars).

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Models the app is allowed to use. An app version that names a model that
// later retires can be kept working by mapping it here instead of shipping
// an update.
export const MODEL_MAP = {
  "claude-haiku-4-5-20251001": "claude-haiku-4-5-20251001",
  "claude-sonnet-4-6": "claude-sonnet-4-6",
};

export const MAX_TOKENS_CAP = 8192; // app's largest request is 8000
const MAX_BODY_BYTES = 30 * 1024 * 1024; // Anthropic's request limit is 32 MB
const ALLOWED_TOOLS = new Set(["web_search_20250305"]);
const FORWARDED_FIELDS = ["model", "max_tokens", "system", "messages", "tools"];
const COUNTER_TTL_SECONDS = 2 * 24 * 60 * 60;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-BeaconAI-Secret",
};

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (err) {
      console.error("unhandled", err && err.stack ? err.stack : err);
      return json({ error: "server_error" }, 500);
    }
  },
};

async function handle(request, env) {
  // The web build calls from a browser; answer its preflight.
  if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (new URL(request.url).pathname !== "/") return json({ error: "not_found" }, 404);

  if (!env.ANTHROPIC_API_KEY || !env.APP_SHARED_SECRET || !env.RATE_LIMIT) {
    console.error("ANTHROPIC_API_KEY, APP_SHARED_SECRET or RATE_LIMIT missing");
    return json({ error: "not_configured" }, 503);
  }
  if (!safeEqual(request.headers.get("X-BeaconAI-Secret") || "", env.APP_SHARED_SECRET)) {
    return json({ error: "unauthorized" }, 401);
  }

  const declared = Number(request.headers.get("Content-Length") || 0);
  if (declared > MAX_BODY_BYTES) return json({ error: "too_large" }, 413);
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: "too_large" }, 413);

  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad_json" }, 400);
  }
  const checked = checkBody(body);
  if (checked.error) return json({ error: checked.error }, 400);

  const limited = await takeQuota(request, env);
  if (limited) {
    return json({ error: "rate_limited", scope: limited }, 429, {
      "Retry-After": String(secondsUntilUtcMidnight()),
    });
  }

  const upstream = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(checked.forward),
  });

  if (upstream.ok) {
    // The app reads content, stop_reason and usage: pass the body through.
    return new Response(upstream.body, {
      status: 200,
      headers: { "Content-Type": "application/json", ...CORS },
    });
  }

  // Never pass upstream error bodies (or anything about the account) back.
  console.error("anthropic", upstream.status, await upstream.text());
  if (upstream.status === 429 || upstream.status === 529) {
    return json({ error: "rate_limited", scope: "upstream" }, 429);
  }
  if (upstream.status === 413) return json({ error: "too_large" }, 413);
  if (upstream.status === 400) return json({ error: "bad_request" }, 400);
  return json({ error: "upstream_error" }, 502);
}

// Validates the request and builds the body that is actually forwarded.
export function checkBody(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { error: "bad_request" };

  const model = MODEL_MAP[body.model];
  if (!model) return { error: "model_not_allowed" };

  const maxTokens = body.max_tokens;
  if (!Number.isInteger(maxTokens) || maxTokens < 1 || maxTokens > MAX_TOKENS_CAP) {
    return { error: "bad_max_tokens" };
  }

  if (!Array.isArray(body.messages) || body.messages.length === 0) return { error: "bad_messages" };

  if (body.system !== undefined && typeof body.system !== "string" && !Array.isArray(body.system)) {
    return { error: "bad_system" };
  }

  if (body.tools !== undefined) {
    if (!Array.isArray(body.tools) || body.tools.length > 1) return { error: "tool_not_allowed" };
    for (const t of body.tools) {
      if (!t || !ALLOWED_TOOLS.has(t.type)) return { error: "tool_not_allowed" };
    }
  }

  const forward = {};
  for (const k of FORWARDED_FIELDS) if (body[k] !== undefined) forward[k] = body[k];
  forward.model = model;
  return { forward };
}

// Checks every quota first and only then counts the request, so a request
// refused by one limit does not use up the others. Returns the name of the
// limit that was hit, or null. KV is eventually consistent, so bursts can
// overshoot slightly; this is a spend guard, not exact metering.
async function takeQuota(request, env) {
  const day = new Date().toISOString().slice(0, 10);
  const ip = await sha256(day + ":" + (request.headers.get("CF-Connecting-IP") || "unknown"));
  const limit = (name, fallback) => {
    const n = parseInt(env[name], 10);
    return Number.isFinite(n) && n >= 0 ? n : fallback;
  };
  const checks = [
    ["global", `g:${day}`, limit("GLOBAL_DAILY", 3000)],
    ["ip", `p:${day}:${ip}`, limit("PER_IP_DAILY", 150)],
  ];
  const counts = await Promise.all(
    checks.map(([, key]) => env.RATE_LIMIT.get(key).then((v) => parseInt(v || "0", 10))),
  );
  const hit = checks.findIndex(([, , max], i) => counts[i] >= max);
  if (hit !== -1) return checks[hit][0];
  await Promise.all(
    checks.map(([, key], i) =>
      env.RATE_LIMIT.put(key, String(counts[i] + 1), { expirationTtl: COUNTER_TTL_SECONDS }),
    ),
  );
  return null;
}

function safeEqual(a, b) {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] || 0) ^ (y[i] || 0);
  return diff === 0;
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function secondsUntilUtcMidnight() {
  const now = new Date();
  const midnight = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(60, Math.ceil((midnight - now.getTime()) / 1000));
}

function json(obj, status = 200, headers = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...CORS, ...headers },
  });
}
