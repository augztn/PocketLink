package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaIndexScanSchedulerTest {
    private lateinit var preferences: android.content.SharedPreferences

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        preferences = context.getSharedPreferences(
            "media-index-scheduler-test",
            Context.MODE_PRIVATE
        )
        preferences.edit().clear().commit()
    }

    @After
    fun tearDown() {
        preferences.edit().clear().commit()
    }

    @Test
    fun configurationClampsIntervalAndInitializesScheduleAnchor() {
        val harness = SchedulerHarness(preferences, initialNowMillis = 100_000L)

        val settings = harness.scheduler.configure(
            enabled = true,
            intervalMinutes = 5,
            scanOnStartup = false,
            scanOnStorageChange = false
        )

        assertEquals(15, settings.getInt("interval_minutes"))
        assertEquals(1_000_000L, settings.getLong("next_scan_at"))
        assertEquals(100_000L, preferences.getLong("schedule_anchor_at", 0L))
        assertFalse(settings.getBoolean("scan_on_startup"))
        assertFalse(settings.getBoolean("scan_on_storage_change"))
    }

    @Test
    fun nextScanUsesActiveScanStartOrMostRecentCompletionBaseline() {
        val harness = SchedulerHarness(preferences, initialNowMillis = 500_000L)
        preferences.edit().putBoolean("automatic_scanning_enabled", true)
            .putInt("scan_interval_minutes", 60).apply()
        harness.lastCompletedAt = 200_000L
        harness.lastAttemptStartedAt = 100_000L

        assertEquals(3_800_000L, harness.scheduler.settings().getLong("next_scan_at"))

        harness.scanning = true
        harness.lastScanStartedAt = 250_000L
        assertEquals(3_850_000L, harness.scheduler.settings().getLong("next_scan_at"))
    }

    @Test
    fun scheduledScanRunsOnlyWhenEnabledAndIntervalHasElapsed() {
        val harness = SchedulerHarness(preferences, initialNowMillis = 1_000_000L)
        preferences.edit()
            .putBoolean("automatic_scanning_enabled", true)
            .putInt("scan_interval_minutes", 15)
            .putLong("schedule_anchor_at", 100_000L)
            .apply()

        harness.now = 999_999L
        harness.scheduler.maybeRunScheduledScan()
        assertTrue(harness.requests.isEmpty())

        harness.now = 1_000_000L
        harness.scheduler.maybeRunScheduledScan()
        assertEquals(listOf(true to "automatic"), harness.requests)

        harness.running = true
        harness.scheduler.maybeRunScheduledScan()
        assertEquals(1, harness.requests.size)

        harness.running = false
        preferences.edit().putBoolean("automatic_scanning_enabled", false).apply()
        harness.scheduler.maybeRunScheduledScan()
        assertEquals(1, harness.requests.size)
    }

    @Test
    fun intervalIsClampedAtMaximumAndDisabledScheduleHasNoNextRun() {
        val harness = SchedulerHarness(preferences, initialNowMillis = 42L)

        val settings = harness.scheduler.configure(
            enabled = false,
            intervalMinutes = 10_000
        )

        assertEquals(1440, settings.getInt("interval_minutes"))
        assertEquals(0L, settings.getLong("next_scan_at"))
    }

    private class SchedulerHarness(
        preferences: android.content.SharedPreferences,
        initialNowMillis: Long
    ) {
        var scanning = false
        var running = false
        var lastScanStartedAt = 0L
        var lastCompletedAt = 0L
        var lastAttemptStartedAt = 0L
        var now = initialNowMillis
        val requests = mutableListOf<Pair<Boolean, String>>()

        val scheduler = MediaIndexScanScheduler(
            preferences = preferences,
            isScanning = { scanning },
            isRunning = { running },
            lastScanStartedAt = { lastScanStartedAt },
            lastCompletedAt = { lastCompletedAt },
            lastAttemptStartedAt = { lastAttemptStartedAt },
            requestScan = { force, trigger -> requests.add(force to trigger) },
            nowMillis = { now }
        )
    }
}
