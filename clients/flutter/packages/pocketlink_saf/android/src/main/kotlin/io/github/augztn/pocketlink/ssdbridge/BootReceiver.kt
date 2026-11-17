package io.github.augztn.pocketlink.ssdbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Restores the host service only when the user has explicitly enabled
 * automatic startup. Android may still deny background service starts.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        val preferences = context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE)
        if (!preferences.getBoolean(PocketLinkSafPlugin.KEY_AUTO_START_ON_BOOT, false)) return

        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BridgeService::class.java)
            )
        } catch (error: Exception) {
            Log.w(TAG, "PocketLink host could not auto-start after boot", error)
        }
    }

    private companion object {
        const val TAG = "PocketLinkBoot"
    }
}
