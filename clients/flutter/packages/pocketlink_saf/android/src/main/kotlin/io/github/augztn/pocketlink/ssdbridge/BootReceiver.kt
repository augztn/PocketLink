package io.github.augztn.pocketlink.ssdbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Restores the PocketLink host only when the user explicitly enables it.
 *
 * Android and OEM background-start policies can still prevent startup; the
 * receiver logs that failure and leaves the user's preference unchanged.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        val preferences = context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE)
        if (!preferences.getBoolean(PocketLinkSafPlugin.KEY_AUTO_START_ON_BOOT, false)) {
            return
        }

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
