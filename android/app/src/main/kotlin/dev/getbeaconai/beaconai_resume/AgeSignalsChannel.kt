package dev.getbeaconai.beaconai_resume

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.play.agesignals.AgeSignalsAccessRequest
import com.google.android.play.agesignals.AgeSignalsException
import com.google.android.play.agesignals.AgeSignalsManager
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.ApplicableAgeFeaturesRequest
import com.google.android.play.agesignals.model.AgeSignalsStatus
import com.google.android.play.agesignals.model.ApplicableAgeFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Thin bridge to the Play Age Signals API (com.google.android.play:age-signals).
 *
 * Contract: method "fetch" ALWAYS replies with success(Map) — never error() —
 * so the Dart side has exactly one shape to parse. Keys:
 *   status   : "shared" | "notShared" | "verificationRequired" |
 *              "notApplicable" | "unavailable" | "error"
 *   ageLower : Int?   (inclusive, only when status == "shared")
 *   ageUpper : Int?   (inclusive, null for the top band, only when "shared")
 *   errorCode: String? (diagnostic only, e.g. "PLAY_-3", "TIMEOUT_check")
 *
 * Flow (approved in Stage 0):
 *   1. getApplicableAgeFeatures — if MANDATORY_SHARING is absent, stop with
 *      "notApplicable". No prompt is ever shown to those users.
 *   2. requestAgeSignalsAccess(activity) — may show the Play prompt.
 *   3. checkAgeSignals — only if step 2 returned SHARED.
 *
 * Nothing here is persisted or logged with age values in release builds;
 * logs are debug-only (FLAG_DEBUGGABLE) and tagged [AGE SIGNAL].
 */
class AgeSignalsChannel(
    messenger: BinaryMessenger,
    private val isDebuggable: Boolean,
    private val activityProvider: () -> Activity?,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.getbeaconai/age_signals"
        private const val TAG = "[AGE SIGNAL]"

        // Non-UI steps: fail fast. The access step may show a Play prompt
        // the user has to read and answer, so it gets a long ceiling.
        private const val QUICK_TIMEOUT_MS = 15_000L
        private const val PROMPT_TIMEOUT_MS = 180_000L
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "fetch" -> fetch(OnceReply(result))
            else -> result.notImplemented()
        }
    }

    // ── Flow ──────────────────────────────────────────────────────────────────

    private fun fetch(reply: OnceReply) {
        val activity = activityProvider()
        if (activity == null || activity.isFinishing) {
            reply.send(unavailable("NO_ACTIVITY"))
            return
        }

        val manager: AgeSignalsManager = try {
            AgeSignalsManagerFactory.create(activity.applicationContext)
        } catch (t: Throwable) {
            reply.send(failure(t, "create"))
            return
        }

        val featuresTask = try {
            manager.getApplicableAgeFeatures(ApplicableAgeFeaturesRequest.builder().build())
        } catch (t: Throwable) {
            reply.send(failure(t, "features"))
            return
        }

        awaitTask(featuresTask, QUICK_TIMEOUT_MS, "features", reply) { features ->
            val set = features?.features() ?: emptySet()
            if (!set.contains(ApplicableAgeFeature.MANDATORY_SHARING)) {
                debugLog("mandatory sharing not applicable; no prompt shown")
                reply.send(mapOf("status" to "notApplicable"))
                return@awaitTask
            }
            requestAccess(manager, reply)
        }
    }

    private fun requestAccess(manager: AgeSignalsManager, reply: OnceReply) {
        val activity = activityProvider()
        if (activity == null || activity.isFinishing) {
            reply.send(unavailable("NO_ACTIVITY"))
            return
        }
        val accessTask = try {
            manager.requestAgeSignalsAccess(
                AgeSignalsAccessRequest.builder().setActivity(activity).build()
            )
        } catch (t: Throwable) {
            reply.send(failure(t, "access"))
            return
        }

        awaitTask(accessTask, PROMPT_TIMEOUT_MS, "access", reply) { access ->
            when (access?.ageSignalsStatus()) {
                AgeSignalsStatus.SHARED -> check(manager, reply)
                AgeSignalsStatus.NOT_SHARED -> reply.send(mapOf("status" to "notShared"))
                AgeSignalsStatus.VERIFICATION_REQUIRED ->
                    reply.send(mapOf("status" to "verificationRequired"))
                else -> reply.send(unavailable("ACCESS_STATUS_${access?.ageSignalsStatus()}"))
            }
        }
    }

    private fun check(manager: AgeSignalsManager, reply: OnceReply) {
        val checkTask = try {
            manager.checkAgeSignals(AgeSignalsRequest.builder().build())
        } catch (t: Throwable) {
            reply.send(failure(t, "check"))
            return
        }
        awaitTask(checkTask, QUICK_TIMEOUT_MS, "check", reply) { signals ->
            // Only the two bounds cross the channel. installId, source tier and
            // significant-change data are deliberately not forwarded — the app
            // stores nothing beyond a bracket.
            reply.send(
                mapOf(
                    "status" to "shared",
                    "ageLower" to signals?.ageLower(),
                    "ageUpper" to signals?.ageUpper(),
                )
            )
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Attaches listeners plus a timeout; whichever fires first wins. */
    private fun <T> awaitTask(
        task: Task<T>,
        timeoutMs: Long,
        step: String,
        reply: OnceReply,
        onSuccess: (T?) -> Unit,
    ) {
        val done = AtomicBoolean(false)
        val timeout = Runnable {
            if (done.compareAndSet(false, true)) {
                debugLog("timeout in step=$step after ${timeoutMs}ms")
                reply.send(mapOf("status" to "error", "errorCode" to "TIMEOUT_$step"))
            }
        }
        mainHandler.postDelayed(timeout, timeoutMs)

        task.addOnSuccessListener { value ->
            if (done.compareAndSet(false, true)) {
                mainHandler.removeCallbacks(timeout)
                try {
                    onSuccess(value)
                } catch (t: Throwable) {
                    reply.send(failure(t, step))
                }
            }
        }
        task.addOnFailureListener { e ->
            if (done.compareAndSet(false, true)) {
                mainHandler.removeCallbacks(timeout)
                reply.send(failure(e, step))
            }
        }
    }

    private fun failure(t: Throwable, step: String): Map<String, Any?> {
        val code = if (t is AgeSignalsException) "PLAY_${t.errorCode}" else t.javaClass.simpleName
        debugLog("failure in step=$step code=$code msg=${t.message}")
        return mapOf("status" to "error", "errorCode" to code)
    }

    private fun unavailable(code: String): Map<String, Any?> {
        debugLog("unavailable: $code")
        return mapOf("status" to "unavailable", "errorCode" to code)
    }

    private fun debugLog(message: String) {
        if (isDebuggable) Log.d(TAG, message)
    }

    /** Guarantees MethodChannel.Result is answered exactly once, on the main thread. */
    private inner class OnceReply(private val result: MethodChannel.Result) {
        private val sent = AtomicBoolean(false)
        fun send(payload: Map<String, Any?>) {
            if (!sent.compareAndSet(false, true)) return
            if (Looper.myLooper() == Looper.getMainLooper()) {
                result.success(payload)
            } else {
                mainHandler.post { result.success(payload) }
            }
        }
    }
}
