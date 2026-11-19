package dev.valroveapp.valrove.assistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * Runs assistant requests in Valrove's Dart code (`assistant_entry.dart`), in
 * a Flutter engine without a screen, so they reuse the app's robot client,
 * room matching and presets. The engine is kept for a few minutes after the
 * last request, then released.
 */
object AssistantBridge {
    private const val CHANNEL = "dev.valroveapp.valrove/assistant"
    private const val LIBRARY = "package:valrove/features/assistant/assistant_entry.dart"
    private const val ENTRY_POINT = "assistantMain"
    private const val IDLE_MILLIS = 3 * 60 * 1000L

    /** An error reported by the Dart side, with its code. */
    class DartError(val code: String, message: String?) : Exception(message)

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready: CompletableDeferred<Unit>? = null
    private val release = Runnable { shutDown() }

    /** Calls [method] in Dart and returns its result (maps, lists, strings). */
    suspend fun call(context: Context, method: String, arguments: Map<String, Any?> = emptyMap()): Any? =
        withContext(Dispatchers.Main) {
            main.removeCallbacks(release)
            try {
                val channel = start(context)
                withTimeout(45_000) { invoke(channel, method, arguments) }
            } finally {
                main.postDelayed(release, IDLE_MILLIS)
            }
        }

    private suspend fun start(context: Context): MethodChannel {
        channel?.let { existing ->
            ready?.await()
            return existing
        }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val newEngine = FlutterEngine(app)
        val gate = CompletableDeferred<Unit>()
        val newChannel = MethodChannel(newEngine.dartExecutor.binaryMessenger, CHANNEL)
        newChannel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                gate.complete(Unit)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        engine = newEngine
        channel = newChannel
        ready = gate
        newEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), LIBRARY, ENTRY_POINT),
        )
        try {
            withTimeout(20_000) { gate.await() }
        } catch (e: TimeoutCancellationException) {
            shutDown()
            throw DartError("unavailable", "Valrove did not start in time")
        }
        return newChannel
    }

    private suspend fun invoke(channel: MethodChannel, method: String, arguments: Map<String, Any?>): Any? =
        suspendCancellableCoroutine { continuation ->
            channel.invokeMethod(
                method,
                arguments,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (continuation.isActive) continuation.resume(result)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        if (continuation.isActive) continuation.resumeWithException(DartError(code, message))
                    }

                    override fun notImplemented() {
                        if (continuation.isActive) {
                            continuation.resumeWithException(DartError("not_implemented", method))
                        }
                    }
                },
            )
        }

    private fun shutDown() {
        engine?.destroy()
        engine = null
        channel = null
        ready = null
    }
}
