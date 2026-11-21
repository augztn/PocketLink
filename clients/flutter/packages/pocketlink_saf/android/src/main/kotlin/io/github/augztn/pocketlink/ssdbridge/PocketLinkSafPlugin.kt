package io.github.augztn.pocketlink.ssdbridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.Settings
import android.provider.DocumentsContract
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class PocketLinkSafPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var mediaChannel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingVolumeId: String? = null
    private var originalVideoBrightness: Float? = null
    private val prefs by lazy { context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE) }
    private var storageManager: StorageManager? = null
    private val volumeCallback by lazy {
        object : StorageManager.StorageVolumeCallback() {
            override fun onStateChanged(volume: StorageVolume) {
                channel.invokeMethod("storageChanged", status())
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pocketlink/saf")
        mediaChannel = MethodChannel(binding.binaryMessenger, "pocketlink/media")
        channel.setMethodCallHandler(this)
        mediaChannel.setMethodCallHandler(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            storageManager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            try {
                storageManager?.registerStorageVolumeCallback(context.mainExecutor, volumeCallback)
            } catch (_: RuntimeException) {
                storageManager = null
            }
        }
        MediaPlaybackBridge.commandHandler = { action, position ->
            mediaChannel.invokeMethod("mediaCommand", mapOf("action" to action, "position" to position))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getVideoBrightness" -> {
                val current = activity
                if (current == null) {
                    result.error("ACTIVITY_UNAVAILABLE", "Video brightness is unavailable.", null)
                    return
                }
                val windowBrightness = current.window.attributes.screenBrightness
                val brightness = if (windowBrightness >= 0f) {
                    windowBrightness
                } else {
                    Settings.System.getInt(
                        context.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS,
                        128
                    ) / 255f
                }
                result.success(brightness.coerceIn(0.01f, 1f).toDouble())
            }
            "setVideoBrightness" -> {
                val current = activity
                val value = call.argument<Number>("brightness")?.toFloat()
                if (current == null || value == null || !value.isFinite()) {
                    result.error("INVALID_BRIGHTNESS", "A valid video brightness value is required.", null)
                    return
                }
                if (originalVideoBrightness == null) {
                    originalVideoBrightness = current.window.attributes.screenBrightness
                }
                val attributes = current.window.attributes
                attributes.screenBrightness = value.coerceIn(0.01f, 1f)
                current.window.attributes = attributes
                result.success(true)
            }
            "restoreVideoBrightness" -> {
                val current = activity
                val original = originalVideoBrightness
                if (current != null && original != null) {
                    val attributes = current.window.attributes
                    attributes.screenBrightness = original
                    current.window.attributes = attributes
                }
                originalVideoBrightness = null
                result.success(true)
            }
            "mediaStart", "mediaUpdate" -> {
                val intent = Intent(context, MediaPlaybackService::class.java).apply {
                    action = MediaPlaybackService.ACTION_UPDATE
                    putExtra(MediaPlaybackService.EXTRA_TITLE, call.argument<String>("title") ?: "PocketLink")
                    putExtra(MediaPlaybackService.EXTRA_ARTIST, call.argument<String>("artist") ?: "Personal music library")
                    putExtra(MediaPlaybackService.EXTRA_PLAYING, call.argument<Boolean>("playing") ?: false)
                    putExtra(MediaPlaybackService.EXTRA_POSITION, call.argument<Number>("positionMs")?.toLong() ?: 0L)
                    putExtra(MediaPlaybackService.EXTRA_DURATION, call.argument<Number>("durationMs")?.toLong() ?: 0L)
                }
                try {
                    if (call.method == "mediaStart") {
                        ContextCompat.startForegroundService(context, intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(true)
                } catch (error: Exception) {
                    result.error("MEDIA_SERVICE_START_FAILED", error.message ?: "Could not start media controls.", null)
                }
            }
            "mediaStop" -> {
                context.stopService(Intent(context, MediaPlaybackService::class.java))
                result.success(true)
            }
            "status" -> result.success(status())
            "mediaIndexStatus" -> result.success(BridgeService.mediaIndexStatus())
            "refreshMediaIndex" -> {
                val scanStatus = BridgeService.refreshMediaIndex()
                if (scanStatus == null) {
                    result.error("SERVER_NOT_RUNNING", "Start the native PocketLink server before scanning device media.", null)
                } else {
                    result.success(scanStatus)
                }
            }
            "requestBackgroundAccess" -> result.success(requestBackgroundAccess())
            "openBackgroundAccessSettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("BACKGROUND_SETTINGS_FAILED", error.message ?: "Could not open battery settings.", null)
                }
            }
            "token" -> result.success(ensureToken())
            "serverPasswordConfigured" -> result.success(ServerCredentials(context).isConfigured())
            "setServerPassword" -> {
                val password = call.argument<String>("password")
                if (password.isNullOrEmpty()) {
                    result.error("INVALID_PASSWORD", "A server password is required.", null)
                    return
                }
                try {
                    ServerCredentials(context).setPassword(password)
                    result.success(true)
                } catch (error: IllegalArgumentException) {
                    result.error("INVALID_PASSWORD", error.message, null)
                } catch (error: Exception) {
                    result.error("PASSWORD_SAVE_FAILED", error.message ?: "Could not save server password.", null)
                }
            }
            "internalStorageStatus" -> result.success(internalStorageGranted())
            "requestInternalStorageAccess" -> {
                val current = activity
                if (current == null) {
                    result.error("UNAVAILABLE", "Android settings cannot be opened right now.", null)
                    return
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.success(true)
                    return
                }
                if (internalStorageGranted()) {
                    result.success(true)
                    return
                }
                try {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:${context.packageName}")
                    )
                    current.startActivity(intent)
                    result.success(false)
                } catch (_: Exception) {
                    try {
                        current.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        result.success(false)
                    } catch (error: Exception) {
                        result.error("PERMISSION_SETTINGS_FAILED", error.message ?: "Could not open all-files access settings.", null)
                    }
                }
            }
            "selectVolume" -> {
                val requestedId = call.argument<String>("volumeId")
                val slot = call.argument<Int>("slot")
                val volume = discoverVolumes().firstOrNull { it.first == requestedId }
                val id = requestedId ?: slot?.takeIf { it in 1..2 }?.let { "usb$it" }
                val current = activity
                val manualPicker = requestedId?.matches(Regex("usb-manual-[a-f0-9]{16}")) == true
                if (id == null || current == null || pendingVolumeId != null ||
                    (requestedId != null && volume == null && !manualPicker)) {
                    result.error("UNAVAILABLE", "Storage picker is unavailable or the drive is no longer connected.", null)
                    return
                }
                pendingVolumeId = id
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && volume != null) {
                    volume.second.createOpenDocumentTreeIntent()
                } else {
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                }.apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
                try {
                    current.startActivityForResult(intent, REQUEST_TREE)
                    result.success(null)
                } catch (error: Exception) {
                    pendingVolumeId = null
                    result.error("PICKER_FAILED", error.message ?: "Could not open Android storage picker.", null)
                }
            }
            "start" -> {
                ensureToken()
                BridgeService.lastError = null
                val intent = Intent(context, BridgeService::class.java)
                try {
                    ContextCompat.startForegroundService(context, intent)
                    result.success(true)
                } catch (error: Exception) {
                    BridgeService.lastError = error.message ?: "Could not start the Android storage service."
                    result.error("START_FAILED", BridgeService.lastError, null)
                }
            }
            "getAutoStartOnBoot" -> result.success(
                prefs.getBoolean(KEY_AUTO_START_ON_BOOT, false)
            )
            "setAutoStartOnBoot" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val saved = prefs.edit()
                    .putBoolean(KEY_AUTO_START_ON_BOOT, enabled)
                    .commit()
                if (saved) {
                    result.success(enabled)
                } else {
                    result.error(
                        "AUTO_START_SAVE_FAILED",
                        "Could not save the automatic startup preference.",
                        null
                    )
                }
            }
            "stop" -> {
                context.stopService(Intent(context, BridgeService::class.java))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestBackgroundAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(context.packageName)) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${context.packageName}"))
            val current = activity
            if (current != null) current.startActivity(intent)
            else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            false
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                val current = activity
                if (current != null) current.startActivity(intent)
                else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                false
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun backgroundAccessGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun internalStorageGranted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

    private fun status(): Map<String, Any?> = mapOf(
        "usb1" to volumeName("usb1"),
        "usb2" to volumeName("usb2"),
        "discoveredVolumes" to discoverVolumes().map { (id, volume) ->
            val directory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) volume.directory else null
            val directAccess = internalStorageGranted() && directory?.isDirectory == true &&
                directory.canRead() && directory.listFiles() != null
            val safSelected = prefs.getString("volume_uri_$id", null) != null
            mapOf(
                "id" to id,
                "name" to volume.getDescription(context),
                "selected" to (directAccess || safSelected),
                "access" to when {
                    directAccess -> "direct"
                    safSelected -> "saf"
                    else -> "not_granted"
                },
                "readable" to (directAccess || safSelected),
                "writable" to if (directAccess) directory?.canWrite() == true else safSelected,
                "state" to volume.state
            )
        },
        "running" to BridgeService.isRunning,
        "apiRunning" to BridgeService.apiRunning,
        "bridgeRunning" to BridgeService.bridgeRunning,
        "error" to BridgeService.lastError,
        "internalStorageGranted" to internalStorageGranted(),
        "backgroundAccessGranted" to backgroundAccessGranted(),
        "serverPasswordConfigured" to ServerCredentials(context).isConfigured()
    )

    private fun discoverVolumes(): List<Pair<String, StorageVolume>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return emptyList()
        val manager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: return emptyList()
        return manager.storageVolumes.mapIndexedNotNull { index, volume ->
            if (!volume.isRemovable || volume.state !in setOf(
                    Environment.MEDIA_MOUNTED,
                    Environment.MEDIA_MOUNTED_READ_ONLY
                )) return@mapIndexedNotNull null
            val identity = externalVolumeIdentity(
                uuid = volume.uuid,
                directoryPath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) volume.directory?.absolutePath else null,
                description = volume.getDescription(context).toString()
            )
            externalVolumeKey(identity) to volume
        }
    }

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
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()
    private fun detachActivity() {
        binding?.removeActivityResultListener(this)
        if (pendingVolumeId != null) {
            pendingVolumeId = null
            channel.invokeMethod("selectionCancelled", null)
        }
        binding = null
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_TREE) return false
        val volumeId = pendingVolumeId
        pendingVolumeId = null
        if (volumeId == null || resultCode != Activity.RESULT_OK || data?.data == null) {
            channel.invokeMethod("selectionCancelled", null)
            return true
        }
        val uri = data.data!!
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            context.contentResolver.takePersistableUriPermission(uri, flags)
            val rootName = DocumentFile.fromTreeUri(context, uri)?.name ?: volumeId
            prefs.edit()
                .putString("volume_uri_$volumeId", uri.toString())
                .putString("volume_name_$volumeId", rootName)
                .apply()
            channel.invokeMethod("storageChanged", status())
        } catch (error: SecurityException) {
            channel.invokeMethod("storageError", error.message ?: "Could not persist storage permission.")
        }
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MediaPlaybackBridge.commandHandler = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try { storageManager?.unregisterStorageVolumeCallback(volumeCallback) } catch (_: RuntimeException) { }
        }
        storageManager = null
        channel.setMethodCallHandler(null)
        mediaChannel.setMethodCallHandler(null)
    }

    companion object {
        private const val REQUEST_TREE = 8764
        const val KEY_AUTO_START_ON_BOOT = "auto_start_on_boot"
    }
}