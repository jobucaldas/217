package com.jobucaldas.a217

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Share sheet (lib/src/platform/share_sheet.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jobucaldas.a217/intents")
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
                    else -> result.notImplemented()
                }
            }
    }
}
