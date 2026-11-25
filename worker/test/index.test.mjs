import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker, { checkBody, MAX_TOKENS_CAP } from "../src/index.js";

const SECRET = "test-secret";
let kv;
let upstreamCalls;
let upstreamResponse;
const realFetch = globalThis.fetch;

function env(over = {}) {
  return {
    ANTHROPIC_API_KEY: "sk-test",
    APP_SHARED_SECRET: SECRET,
    RATE_LIMIT: kv,
    PER_IP_DAILY: "3",
    GLOBAL_DAILY: "100",
    ...over,
  };
}

function req(body, { secret = SECRET, path = "/", method = "POST", ip = "1.2.3.4" } = {}) {
  const headers = { "Content-Type": "application/json", "CF-Connecting-IP": ip };
  if (secret !== null) headers["X-BeaconAI-Secret"] = secret;
  return new Request("https://beaconai-resume-proxy.example.workers.dev" + path, {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const ok = () => ({
  model: "claude-haiku-4-5-20251001",
  max_tokens: 2000,
  system: "You extract resume fields.",
  messages: [{ role: "user", content: "hello" }],
});

beforeEach(() => {
  const store = new Map();
  kv = {
    get: async (k) => (store.has(k) ? store.get(k) : null),
    put: async (k, v) => void store.set(k, v),
  };
  upstreamCalls = [];
  upstreamResponse = () =>
    new Response(JSON.stringify({ content: [{ type: "text", text: "hi" }], stop_reason: "end_turn" }), {
      status: 200,
    });
  globalThis.fetch = async (url, init) => {
    upstreamCalls.push({ url, init, body: JSON.parse(init.body) });
    return upstreamResponse();
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

test("a valid Resume request is forwarded and the response passed through", async () => {
  const res = await worker.fetch(req(ok()), env());
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { content: [{ type: "text", text: "hi" }], stop_reason: "end_turn" });
  assert.equal(upstreamCalls.length, 1);
  assert.equal(upstreamCalls[0].url, "https://api.anthropic.com/v1/messages");
  assert.equal(upstreamCalls[0].init.headers["x-api-key"], "sk-test");
  assert.equal(upstreamCalls[0].body.model, "claude-haiku-4-5-20251001");
});

test("the Sonnet generation model and the web search tool are allowed", async () => {
  const body = { ...ok(), model: "claude-sonnet-4-6", tools: [{ type: "web_search_20250305", name: "web_search" }] };
  const res = await worker.fetch(req(body), env());
  assert.equal(res.status, 200);
  assert.deepEqual(upstreamCalls[0].body.tools, body.tools);
});

test("PDF document blocks pass through untouched", async () => {
  const content = [
    { type: "document", source: { type: "base64", media_type: "application/pdf", data: "JVBERi0x" } },
    { type: "text", text: "Extract all resume information." },
  ];
  const res = await worker.fetch(req({ ...ok(), messages: [{ role: "user", content }] }), env());
  assert.equal(res.status, 200);
  assert.deepEqual(upstreamCalls[0].body.messages[0].content, content);
});

test("missing or wrong secret → 401, nothing forwarded", async () => {
  assert.equal((await worker.fetch(req(ok(), { secret: null }), env())).status, 401);
  assert.equal((await worker.fetch(req(ok(), { secret: "nope" }), env())).status, 401);
  assert.equal(upstreamCalls.length, 0);
});

test("other paths → 404, GET → 405, OPTIONS → CORS preflight", async () => {
  assert.equal((await worker.fetch(req(ok(), { path: "/v1/messages" }), env())).status, 404);
  assert.equal((await worker.fetch(req(null, { method: "GET" }), env())).status, 405);
  const pre = await worker.fetch(req(null, { method: "OPTIONS" }), env());
  assert.equal(pre.status, 200);
  assert.match(pre.headers.get("Access-Control-Allow-Headers"), /X-BeaconAI-Secret/);
});

test("unconfigured Worker fails closed with 503", async () => {
  const res = await worker.fetch(req(ok()), env({ APP_SHARED_SECRET: undefined }));
  assert.equal(res.status, 503);
  assert.equal(upstreamCalls.length, 0);
});

test("checkBody rejects models, token limits and tools the app never uses", () => {
  assert.equal(checkBody({ ...ok(), model: "claude-opus-5-5" }).error, "model_not_allowed");
  assert.equal(checkBody({ ...ok(), max_tokens: MAX_TOKENS_CAP + 1 }).error, "bad_max_tokens");
  assert.equal(checkBody({ ...ok(), max_tokens: "100" }).error, "bad_max_tokens");
  assert.equal(checkBody({ ...ok(), messages: [] }).error, "bad_messages");
  assert.equal(checkBody({ ...ok(), tools: [{ type: "bash_20250124", name: "bash" }] }).error, "tool_not_allowed");
  assert.equal(checkBody([1]).error, "bad_request");
});

test("unknown top-level fields are dropped, not forwarded", () => {
  const { forward } = checkBody({ ...ok(), metadata: { user_id: "x" }, stream: true, temperature: 1 });
  assert.deepEqual(Object.keys(forward).sort(), ["max_tokens", "messages", "model", "system"]);
});

test("per-IP daily quota → 429 with Retry-After; other IPs unaffected", async () => {
  for (let i = 0; i < 3; i++) assert.equal((await worker.fetch(req(ok()), env())).status, 200);
  const limited = await worker.fetch(req(ok()), env());
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.headers.get("Retry-After")) >= 60);
  assert.equal((await worker.fetch(req(ok(), { ip: "5.6.7.8" }), env())).status, 200);
});

test("global daily cap applies across IPs", async () => {
  const e = env({ GLOBAL_DAILY: "2", PER_IP_DAILY: "100" });
  assert.equal((await worker.fetch(req(ok(), { ip: "a" }), e)).status, 200);
  assert.equal((await worker.fetch(req(ok(), { ip: "b" }), e)).status, 200);
  assert.equal((await worker.fetch(req(ok(), { ip: "c" }), e)).status, 429);
});

test("upstream errors are mapped and their bodies never leaked", async () => {
  const cases = [
    [500, 502],
    [529, 429],
    [429, 429],
    [400, 400],
    [413, 413],
  ];
  for (const [up, expected] of cases) {
    upstreamResponse = () => new Response('{"error":{"message":"org secret details"}}', { status: up });
    const res = await worker.fetch(req(ok(), { ip: "ip" + up }), env());
    assert.equal(res.status, expected, `upstream ${up}`);
    assert.doesNotMatch(await res.text(), /secret details/);
  }
});

test("oversized bodies are refused before parsing", async () => {
  const r = new Request("https://x.workers.dev/", {
    method: "POST",
    headers: { "X-BeaconAI-Secret": SECRET, "Content-Length": String(31 * 1024 * 1024) },
    body: "{}",
  });
  assert.equal((await worker.fetch(r, env())).status, 413);
});
