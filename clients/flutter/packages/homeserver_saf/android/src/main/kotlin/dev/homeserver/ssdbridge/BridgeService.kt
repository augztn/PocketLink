package dev.homeserver.ssdbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class BridgeService : Service() {
    private var bridgeServer: SafHttpServer? = null
    private var apiServer: NativeApiServer? = null

    override fun onCreate() {
        super.onCreate()
        val channelId = "homeserver-ssd-bridge"
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(channelId, "HomeServer server", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("HomeServer")
            .setContentText("Your HomeServer service is running")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
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
                apiServer = NativeApiServer(this, credentials).also { it.start() }
                apiRunning = true
            }

            check(bridgeRunning || apiRunning) {
                "Set a native server password or configure USB storage before starting HomeServer."
            }
            lastError = null
            isRunning = true
        } catch (error: Exception) {
            stopServers()
            lastError = error.message ?: "Could not start the HomeServer service."
            stopForeground(true)
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        stopServers()
        super.onDestroy()
    }

    private fun stopServers() {
        try { apiServer?.stop() } catch (_: Exception) { }
        try { bridgeServer?.stop() } catch (_: Exception) { }
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
    }
}
