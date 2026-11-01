package com.caldasstudios.app217

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Share sheet (lib/src/platform/share_sheet.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.caldasstudios.app217/intents")
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
        // Session renewal key (lib/src/auth/device_key.dart): the private half
        // never leaves the Keystore; the server only ever sees signatures.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.caldasstudios.app217/device_key")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "create" -> result.success(createDeviceKey())
                        "sign" -> {
                            val message = call.argument<ByteArray>("message")
                            val key = keyStore().getKey(DEVICE_KEY_ALIAS, null) as? PrivateKey
                            if (message == null || key == null) {
                                result.error("no_key", "no device key", null)
                            } else {
                                result.success(Signature.getInstance("SHA256withECDSA").run {
                                    initSign(key); update(message); sign()
                                })
                            }
                        }
                        "delete" -> { keyStore().deleteEntry(DEVICE_KEY_ALIAS); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("device_key", e.message, null)
                }
            }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    /** New P-256 signing key (StrongBox when the phone has one); returns its PKIX public key. */
    private fun createDeviceKey(): ByteArray {
        keyStore().deleteEntry(DEVICE_KEY_ALIAS)
        fun generate(strongBox: Boolean): ByteArray {
            val spec = KeyGenParameterSpec.Builder(DEVICE_KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .apply { if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) setIsStrongBoxBacked(true) }
                .build()
            return KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
                .apply { initialize(spec) }
                .generateKeyPair().public.encoded
        }
        return try { generate(true) } catch (e: Exception) { generate(false) }
    }

    companion object {
        private const val DEVICE_KEY_ALIAS = "217_device_key"
    }
}
