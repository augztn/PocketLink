package io.github.augztn.pocketlink.ssdbridge

import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Owns automatic scan scheduling policy and its persisted preferences.
 *
 * Scan execution, dirty-pass coalescing, and scanner lifecycle remain owned by
 * [MediaIndexScanner].
 */
internal class MediaIndexScanScheduler(
    private val preferences: SharedPreferences,
    private val isScanning: () -> Boolean,
    private val isRunning: () -> Boolean,
    private val lastScanStartedAt: () -> Long,
    private val lastCompletedAt: () -> Long,
    private val lastAttemptStartedAt: () -> Long,
    private val requestScan: (force: Boolean, trigger: String) -> Unit,
    private val nowMillis: () -> Long = System::currentTimeMillis
) {
    fun automaticScanningEnabled(): Boolean =
        preferences.getBoolean(KEY_AUTOMATIC_ENABLED, true)

    fun scanOnStartupEnabled(): Boolean =
        preferences.getBoolean(KEY_SCAN_ON_STARTUP, true)

    fun scanOnStorageChangeEnabled(): Boolean =
        preferences.getBoolean(KEY_SCAN_ON_STORAGE_CHANGE, true)

    fun scanIntervalMinutes(): Int =
        preferences.getInt(KEY_SCAN_INTERVAL_MINUTES, DEFAULT_INTERVAL_MINUTES)
            .coerceIn(MIN_INTERVAL_MINUTES, MAX_INTERVAL_MINUTES)

    fun ensureScheduleAnchor() {
        if (automaticScanningEnabled() &&
            preferences.getLong(KEY_SCHEDULE_ANCHOR_AT, 0L) == 0L
        ) {
            preferences.edit().putLong(KEY_SCHEDULE_ANCHOR_AT, nowMillis()).apply()
        }
    }

    fun configure(
        enabled: Boolean,
        intervalMinutes: Int,
        scanOnStartup: Boolean = scanOnStartupEnabled(),
        scanOnStorageChange: Boolean = scanOnStorageChangeEnabled()
    ): JSONObject {
        val safeInterval = intervalMinutes.coerceIn(MIN_INTERVAL_MINUTES, MAX_INTERVAL_MINUTES)
        val editor = preferences.edit()
            .putBoolean(KEY_AUTOMATIC_ENABLED, enabled)
            .putBoolean(KEY_SCAN_ON_STARTUP, scanOnStartup)
            .putBoolean(KEY_SCAN_ON_STORAGE_CHANGE, scanOnStorageChange)
            .putInt(KEY_SCAN_INTERVAL_MINUTES, safeInterval)
        if (enabled && lastCompletedAt() == 0L && lastAttemptStartedAt() == 0L &&
            preferences.getLong(KEY_SCHEDULE_ANCHOR_AT, 0L) == 0L
        ) {
            editor.putLong(KEY_SCHEDULE_ANCHOR_AT, nowMillis())
        }
        editor.apply()
        return settings()
    }

    fun settings(): JSONObject {
        val enabled = automaticScanningEnabled()
        val interval = scanIntervalMinutes()
        val baseline = if (isScanning()) {
            lastScanStartedAt()
        } else {
            lastCompletedAt().takeIf { it > 0L }
                ?: lastAttemptStartedAt().takeIf { it > 0L }
                ?: preferences.getLong(KEY_SCHEDULE_ANCHOR_AT, 0L)
        }
        return JSONObject()
            .put("enabled", enabled)
            .put("scan_on_startup", scanOnStartupEnabled())
            .put("scan_on_storage_change", scanOnStorageChangeEnabled())
            .put("interval_minutes", interval)
            .put(
                "next_scan_at",
                if (enabled && baseline > 0L) baseline + interval * MILLIS_PER_MINUTE else 0L
            )
    }

    fun maybeRunScheduledScan() {
        if (!automaticScanningEnabled() || isRunning()) return
        val baseline = lastCompletedAt().takeIf { it > 0L }
            ?: lastAttemptStartedAt().takeIf { it > 0L }
            ?: preferences.getLong(KEY_SCHEDULE_ANCHOR_AT, 0L)
        if (baseline == 0L ||
            nowMillis() - baseline >= scanIntervalMinutes() * MILLIS_PER_MINUTE
        ) {
            requestScan(true, "automatic")
        }
    }

    private companion object {
        const val KEY_AUTOMATIC_ENABLED = "automatic_scanning_enabled"
        const val KEY_SCAN_ON_STARTUP = "scan_on_startup"
        const val KEY_SCAN_ON_STORAGE_CHANGE = "scan_on_storage_change"
        const val KEY_SCAN_INTERVAL_MINUTES = "scan_interval_minutes"
        const val KEY_SCHEDULE_ANCHOR_AT = "schedule_anchor_at"
        const val DEFAULT_INTERVAL_MINUTES = 60
        const val MIN_INTERVAL_MINUTES = 15
        const val MAX_INTERVAL_MINUTES = 1440
        const val MILLIS_PER_MINUTE = 60_000L
    }
}
