package com.shahzadpoultry.shahzad_poultry

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "shahzad_poultry/whatsapp"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendFile" -> {
                    val path = call.argument<String>("path")
                    val phone = call.argument<String>("phone") // international digits, e.g. 923001234567
                    val text = call.argument<String>("text") ?: ""
                    if (path == null || phone == null) {
                        result.error("bad_args", "path and phone are required", null)
                    } else {
                        result.success(sendFileToChat(path, phone, text))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Opens WhatsApp (or WhatsApp Business) directly in [phone]'s chat with the
     * PDF attached and [text] as caption. The user still presses Send.
     * Returns "opened", "not_installed" or "failed:<reason>".
     */
    private fun sendFileToChat(path: String, phone: String, text: String): String {
        val file = File(path)
        if (!file.exists()) return "failed:file not found"
        val uri = FileProvider.getUriForFile(this, "$packageName.pdfprovider", file)
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            if (!isInstalled(pkg)) continue
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                setPackage(pkg)
                putExtra(Intent.EXTRA_STREAM, uri)
                if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                // Opens that contact's chat directly instead of the contact picker.
                putExtra("jid", "$phone@s.whatsapp.net")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            return try {
                startActivity(intent)
                "opened"
            } catch (e: ActivityNotFoundException) {
                "failed:${e.message}"
            }
        }
        return "not_installed"
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
