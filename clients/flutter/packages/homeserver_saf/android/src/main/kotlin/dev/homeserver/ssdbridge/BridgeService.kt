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
    private var server: SafHttpServer? = null

    override fun onCreate() {
        super.onCreate()
        val channelId = "homeserver-ssd-bridge"
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(channelId, "HomeServer storage", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("HomeServer")
            .setContentText("USB storage access is active")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
            .build()
        startForeground(8765, notification)
        val prefs = getSharedPreferences("ssd-bridge", MODE_PRIVATE)
        server = SafHttpServer(this, prefs.getString("token", "") ?: "").also { it.start() }
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onDestroy() {
        server?.stop()
        server = null
        isRunning = false
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null

    companion object { @Volatile var isRunning: Boolean = false }
}
