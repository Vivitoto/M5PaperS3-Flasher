package vink.flasher

import android.os.Handler
import android.os.Looper
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import com.chaquo.python.PyException

class MainActivity : FlutterActivity() {
    private val channelName = "vink.flasher/esptool"
    private lateinit var channel: MethodChannel
    @Volatile private var cancelRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "runEsptool" -> runEsptool(call, result)
                "cancelEsptool" -> {
                    cancelRequested = true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runEsptool(call: MethodCall, result: MethodChannel.Result) {
        val args = call.argument<List<Any?>>("args")?.map { it.toString() }
        if (args == null || args.isEmpty()) {
            result.error("bad_args", "Missing esptool arguments", null)
            return
        }

        cancelRequested = false
        Thread {
            try {
                emitLog("esptool args: ${args.joinToString(" ")}")
                val py = Python.getInstance()
                val bridge = py.getModule("esptool_bridge")
                val callback = EsptoolCallback()
                val response = bridge.callAttr("run_esptool", this, args, callback).toString()
                val json = JSONObject(response)
                val success = json.optBoolean("success", false)
                val output = json.optString("output", "")
                val cancelled = json.optBoolean("cancelled", false)
                mainHandler.post {
                    result.success(
                        mapOf(
                            "success" to success,
                            "output" to output,
                            "cancelled" to cancelled,
                        )
                    )
                }
            } catch (error: Throwable) {
                val details = buildNativeErrorDetails(error)
                emitLog(details)
                mainHandler.post {
                    result.success(
                        mapOf(
                            "success" to false,
                            "output" to details,
                            "cancelled" to false,
                        )
                    )
                }
            }
        }.start()
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private fun buildNativeErrorDetails(error: Throwable): String {
        val pyStack = if (error is PyException) error.stackTraceToString() else null
        val message = error.message?.takeIf { it.isNotBlank() } ?: error::class.java.name
        val javaStack = error.stackTraceToString()
        return listOfNotNull(
            "Native esptool bridge failed: $message",
            pyStack?.let { "Python traceback:\n$it" },
            "Java/Kotlin stacktrace:\n$javaStack",
        ).joinToString("\n")
    }

    private fun emitLog(text: String) {
        if (text.isBlank()) return
        mainHandler.post {
            channel.invokeMethod("esptoolLog", text)
        }
    }

    inner class EsptoolCallback {
        fun emitOutput(text: String) {
            emitLog(text)
        }

        fun shouldCancel(): Boolean = cancelRequested
    }
}
