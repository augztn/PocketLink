package io.github.augztn.pocketlink.ssdbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.app.PendingIntent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.IBinder
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat

class BridgeService : Service() {
    private var bridgeServer: SafHttpServer? = null
    private var apiServer: NativeApiServer? = null
    private var storageReceiverRegistered = false
    private val scanHandler = Handler(Looper.getMainLooper())
    private val scanCheck = object : Runnable {
        override fun run() {
            apiServer?.runScheduledMediaScanCheck()
            scanHandler.postDelayed(this, SCAN_CHECK_INTERVAL_MS)
        }
    }
    private val storageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val connected = intent.action == Intent.ACTION_MEDIA_MOUNTED
            if (intent.action in STORAGE_ACTIONS) {
                val volumeId = intent.data?.path
                    ?.trimEnd('/')
                    ?.substringAfterLast('/')
                    ?.takeIf { it.contains('-') && !it.equals("emulated", ignoreCase = true) }
                    ?.let { externalVolumeKey(externalVolumeIdentity(it, null, it)) }
                apiServer?.onStorageChanged(connected, volumeId)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val channelId = "pocketlink-ssd-bridge"
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.deleteNotificationChannel("homeserver-ssd-bridge")
            val channel = NotificationChannel(channelId, "PocketLink server", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this, 8765, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("PocketLink is running")
            .setContentText("Your personal server is active. Tap to manage storage and connection settings.")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        startForeground(8765, notification)

        try {
            val prefs = getSharedPreferences("ssd-bridge", MODE_PRIVATE)
            val token = prefs.getString("token", null).orEmpty()
            if (token.isNotBlank()) {
                bridgeServer = SafHttpServer(this, token).also { it.start() }
                bridgeRunning = true
            }

            val credentials = ServerCredentials(this)
            if (credentials.isConfigured()) {
                apiServer = NativeApiServer(this, credentials).also {
                    it.start()
                    activeApiServer = it
                    it.ensureMediaIndexStarted()
                }
                apiRunning = true
                val filter = IntentFilter().apply {
                    addAction(Intent.ACTION_MEDIA_MOUNTED)
                    addAction(Intent.ACTION_MEDIA_UNMOUNTED)
                    addAction(Intent.ACTION_MEDIA_EJECT)
                    addAction(Intent.ACTION_MEDIA_REMOVED)
                    addDataScheme("file")
                }
                ContextCompat.registerReceiver(
                    this, storageReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
                )
                storageReceiverRegistered = true
                scanHandler.postDelayed(scanCheck, SCAN_CHECK_INTERVAL_MS)
            }

            check(bridgeRunning || apiRunning) {
                "Set a native server password or configure USB storage before starting PocketLink."
            }
            lastError = null
            isRunning = true
        } catch (error: Exception) {
            stopServers()
            lastError = error.message ?: "Could not start the PocketLink service."
            stopForegroundCompat()
            stopSelf()
        }
    }

    // Android may recreate this service with a null intent after reclaiming
    // the process. onCreate() rehydrates both listeners from persisted credentials.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        scanHandler.removeCallbacks(scanCheck)
        if (storageReceiverRegistered) {
            runCatching { unregisterReceiver(storageReceiver) }
            storageReceiverRegistered = false
        }
        stopServers()
        super.onDestroy()
    }

    private fun stopServers() {
        try { apiServer?.stop() } catch (_: Exception) { }
        try { apiServer?.closeMediaIndex() } catch (_: Exception) { }
        try { bridgeServer?.stop() } catch (_: Exception) { }
        apiServer?.let { if (activeApiServer === it) activeApiServer = null }
        apiServer = null
        bridgeServer = null
        apiRunning = false
        bridgeRunning = false
        isRunning = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        @Volatile var isRunning: Boolean = false
        @Volatile var apiRunning: Boolean = false
        @Volatile var bridgeRunning: Boolean = false
        @Volatile var lastError: String? = null
        @Volatile private var activeApiServer: NativeApiServer? = null
        private const val SCAN_CHECK_INTERVAL_MS = 60_000L
        private val STORAGE_ACTIONS = setOf(
            Intent.ACTION_MEDIA_MOUNTED,
            Intent.ACTION_MEDIA_UNMOUNTED,
            Intent.ACTION_MEDIA_EJECT,
            Intent.ACTION_MEDIA_REMOVED
        )

        fun mediaIndexStatus(): String? = activeApiServer?.mediaIndexStatus()

        fun refreshMediaIndex(): String? = activeApiServer?.refreshMediaIndex()
    }
}
