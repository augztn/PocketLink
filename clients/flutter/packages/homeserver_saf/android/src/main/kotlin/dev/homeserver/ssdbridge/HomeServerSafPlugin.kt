package dev.homeserver.ssdbridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class HomeServerSafPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    ActivityPluginBinding.OnSaveInstanceStateListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingSlot: Int? = null
    private val prefs by lazy { context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE) }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "homeserver/saf")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "token" -> result.success(ensureToken())
            "selectVolume" -> {
                val slot = call.argument<Int>("slot")
                val current = activity
                if (slot !in 1..2 || current == null || pendingSlot != null) {
                    result.error("UNAVAILABLE", "Storage picker is unavailable.", null)
                    return
                }
                pendingSlot = slot
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
                current.startActivityForResult(intent, REQUEST_TREE)
                result.success(null)
            }
            "start" -> {
                val intent = Intent(context, BridgeService::class.java)
                ContextCompat.startForegroundService(context, intent)
                result.success(true)
            }
            "stop" -> {
                context.stopService(Intent(context, BridgeService::class.java))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> = mapOf(
        "usb1" to volumeName("usb1"),
        "usb2" to volumeName("usb2"),
        "running" to BridgeService.isRunning
    )

    private fun volumeName(key: String): String {
        val raw = prefs.getString(key, null) ?: return "Not selected"
        return try {
            DocumentFile.fromTreeUri(context, Uri.parse(raw))?.name ?: "Permission unavailable"
        } catch (_: SecurityException) { "Permission revoked" }
    }

    private fun ensureToken(): String {
        prefs.getString("token", null)?.let { return it }
        val bytes = ByteArray(32).also { java.security.SecureRandom().nextBytes(it) }
        val token = android.util.Base64.encodeToString(
            bytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING
        )
        prefs.edit().putString("token", token).apply()
        return token
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        this.binding = binding
        binding.addActivityResultListener(::onActivityResult)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()
    private fun detachActivity() {
        binding?.removeActivityResultListener(::onActivityResult)
        binding = null
        activity = null
    }

    private fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_TREE) return false
        val slot = pendingSlot
        pendingSlot = null
        if (slot == null || resultCode != Activity.RESULT_OK || data?.data == null) {
            channel.invokeMethod("selectionCancelled", null)
            return true
        }
        val uri = data.data!!
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            context.contentResolver.takePersistableUriPermission(uri, flags)
            prefs.edit().putString("usb$slot", uri.toString()).apply()
            channel.invokeMethod("storageChanged", status())
        } catch (error: SecurityException) {
            channel.invokeMethod("storageError", error.message ?: "Could not persist storage permission.")
        }
        return true
    }

    override fun onSaveInstanceState(outState: android.os.Bundle) = Unit
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    companion object { private const val REQUEST_TREE = 8764 }
}
