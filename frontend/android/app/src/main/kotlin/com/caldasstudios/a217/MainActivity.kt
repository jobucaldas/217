package com.caldasstudios.a217

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Share sheet (lib/src/platform/share_sheet.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.caldasstudios.a217/intents")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrEmpty()) {
                            result.error("bad_args", "text is required", null)
                            return@setMethodCallHandler
                        }
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                            call.argument<String>("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                        }
                        startActivity(Intent.createChooser(send, null))
                        result.success(null)
                    }
                    "shareFile" -> {
                        val name = call.argument<String>("name")
                        val content = call.argument<String>("content")
                        if (name.isNullOrBlank() || content == null || !name.endsWith(".json")) { result.error("bad_args", "JSON name and content are required", null); return@setMethodCallHandler }
                        try {
                            val dir = File(cacheDir, "exports").apply { mkdirs() }
                            val file = File(dir, name).apply { writeText(content, Charsets.UTF_8) }
                            val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val send = Intent(Intent.ACTION_SEND).apply { type = "application/json"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                            startActivity(Intent.createChooser(send, null)); result.success(null)
                        } catch (e: Exception) { result.error("share_failed", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
