package vink.flasher

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import com.chaquo.python.PyException
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val channelName = "vink.flasher/esptool"
    private val updateChannelName = "vink.flasher/app_update"
    private lateinit var channel: MethodChannel
    private lateinit var updateChannel: MethodChannel
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
                "flashPaperS3Native" -> flashPaperS3Native(call, result)
                "cancelEsptool" -> {
                    cancelRequested = true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
        updateChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadApkToDownloads" -> downloadApkToDownloads(call, result)
                "installApk" -> installApk(call, result)
                else -> result.notImplemented()
            }
        }
    }


    private fun downloadApkToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val rawName = call.argument<String>("name") ?: "vink-flasher-update.apk"
        val expectedSize = call.argument<Number>("size")?.toLong()
        if (url.isNullOrBlank()) {
            result.error("bad_args", "Missing apk url", null)
            return
        }
        val name = rawName.replace(Regex("[^A-Za-z0-9._-]"), "_")

        Thread {
            try {
                val downloaded = writeApkToPublicDownloads(url, name, expectedSize)
                mainHandler.post { result.success(downloaded) }
            } catch (error: Throwable) {
                val details = buildNativeErrorDetails(error)
                mainHandler.post { result.error("download_failed", details, null) }
            }
        }.start()
    }

    private fun writeApkToPublicDownloads(url: String, name: String, expectedSize: Long?): Map<String, Any?> {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 30_000
            readTimeout = 30_000
            requestMethod = "GET"
        }
        val total = expectedSize ?: connection.contentLengthLong.takeIf { it > 0 }
        if (connection.responseCode !in 200..299) {
            throw IllegalStateException("APK download failed: HTTP ${connection.responseCode}")
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            writeApkToMediaStore(connection, name, total)
        } else {
            writeApkToLegacyDownloads(connection, name, total)
        }
    }

    private fun writeApkToMediaStore(connection: HttpURLConnection, name: String, total: Long?): Map<String, Any?> {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        resolver.query(
            collection,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME}=?",
            arrayOf(name),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                resolver.delete(Uri.withAppendedPath(collection, id.toString()), null, null)
            }
        }

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/vnd.android.package-archive")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Unable to create APK in system Downloads")
        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                streamHttpToOutput(connection, output, total)
            } ?: throw IllegalStateException("Unable to open Downloads output stream")
            val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
            return mapOf("uri" to uri.toString(), "path" to null)
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        } finally {
            connection.disconnect()
        }
    }

    private fun writeApkToLegacyDownloads(connection: HttpURLConnection, name: String, total: Long?): Map<String, Any?> {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, name)
        if (file.exists()) file.delete()
        FileOutputStream(file).use { output -> streamHttpToOutput(connection, output, total) }
        connection.disconnect()
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        return mapOf("uri" to uri.toString(), "path" to file.absolutePath)
    }

    private fun streamHttpToOutput(connection: HttpURLConnection, output: java.io.OutputStream, total: Long?) {
        val buffer = ByteArray(128 * 1024)
        var received = 0L
        connection.inputStream.use { input ->
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                output.write(buffer, 0, read)
                received += read.toLong()
                emitApkProgress(received, total)
            }
        }
        output.flush()
        if (total != null && total > 0 && received != total) {
            throw IllegalStateException("APK size mismatch: expected $total bytes, got $received bytes")
        }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        if (uriText.isNullOrBlank()) {
            result.error("bad_args", "Missing APK uri", null)
            return
        }
        try {
            val uri = Uri.parse(uriText)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Throwable) {
            result.error("install_failed", error.message, null)
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

    private fun flashPaperS3Native(call: MethodCall, result: MethodChannel.Result) {
        val deviceName = call.argument<String>("deviceName")
        val firmwarePath = call.argument<String>("firmwarePath")
        val flashOffset = call.argument<Int>("flashOffset") ?: 0
        val baudRate = call.argument<Int>("baudRate") ?: 921600
        val reboot = call.argument<Boolean>("reboot") ?: true
        if (firmwarePath.isNullOrBlank()) {
            result.error("bad_args", "Missing firmwarePath", null)
            return
        }

        cancelRequested = false
        Thread {
            try {
                emitLog("native PaperS3 flash: device=$deviceName baud=$baudRate offset=0x${flashOffset.toString(16)}")
                PaperS3NativeFlasher(
                    context = this,
                    shouldCancel = { cancelRequested },
                    emitLog = { emitLog(it) },
                    emitProgress = { emitPaperS3Progress(it) },
                ).flash(
                    deviceName = deviceName,
                    firmwarePath = firmwarePath,
                    flashOffset = flashOffset,
                    baudRate = baudRate,
                    reboot = reboot,
                )
                mainHandler.post {
                    result.success(
                        mapOf(
                            "success" to true,
                            "output" to "Native PaperS3 flash complete",
                            "cancelled" to false,
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
                            "cancelled" to (error is InterruptedException),
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

    private fun emitPaperS3Progress(progress: Map<String, Any>) {
        mainHandler.post {
            channel.invokeMethod("paperS3Progress", progress)
        }
    }

    private fun emitApkProgress(receivedBytes: Long, totalBytes: Long?) {
        mainHandler.post {
            updateChannel.invokeMethod(
                "apkDownloadProgress",
                mapOf(
                    "receivedBytes" to receivedBytes,
                    "totalBytes" to totalBytes,
                )
            )
        }
    }

    inner class EsptoolCallback {
        fun emitOutput(text: String) {
            emitLog(text)
        }

        fun shouldCancel(): Boolean = cancelRequested
    }
}
