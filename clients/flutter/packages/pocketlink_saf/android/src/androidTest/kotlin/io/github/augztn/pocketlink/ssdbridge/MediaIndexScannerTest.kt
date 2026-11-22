package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.os.SystemClock
import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class MediaIndexScannerTest {
    @Test
    fun emptyExternalDirectoryListingRetainsPreviouslyIndexedMedia() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val internalRoot = File(context.cacheDir, "media-index-empty-internal").apply {
            deleteRecursively()
            mkdirs()
        }
        val externalRoot = File(context.cacheDir, "media-index-empty-external").apply {
            deleteRecursively()
            mkdirs()
        }
        val music = File(externalRoot, "Music").apply { mkdirs() }
        val track = File(music, "track.mp3").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        val scanner = MediaIndexScanner(
            context,
            { internalRoot },
            { listOf("usb-test" to DocumentFile.fromFile(externalRoot)) }
        )
        try {
            scanner.requestScan(force = true)
            val first = awaitFinished(scanner)
            assertEquals("complete", first.getString("state"))
            assertEquals(1, first.getInt("music_count"))

            assertTrue(track.delete())
            SystemClock.sleep(5)
            scanner.requestScan(force = true)
            val second = awaitFinished(scanner, first.getLong("last_scan_started_at"))
            assertEquals("partial", second.getString("state"))
            assertEquals("Previously indexed media must not be pruned after an empty SAF listing", 1, second.getInt("music_count"))
            assertTrue(
                (0 until second.getJSONArray("skipped_items").length()).any { index ->
                    second.getJSONArray("skipped_items").getJSONObject(index)
                        .getString("reason").contains("empty listing")
                }
            )
        } finally {
            scanner.close()
            internalRoot.deleteRecursively()
            externalRoot.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @Test
    fun emptyProviderListingRetainsPreviouslyIndexedDescendants() {
        val indexed = setOf("Music", "Music/track.mp3", "Music/Live/set.flac", "Pictures")
        assertTrue(hasIndexedDescendants(indexed, ""))
        assertTrue(hasIndexedDescendants(indexed, "Music"))
        assertTrue(!hasIndexedDescendants(indexed, "Pictures"))
        assertTrue(!hasIndexedDescendants(indexed, "Music/Live/set.flac"))
    }

    @Test
    fun scansInternalFilesAndPrunesDeletedEntriesAfterACompleteRefresh() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            // Keep startup/storage observers from racing the explicitly manual scan.
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val root = File(context.cacheDir, "media-index-test").apply {
            deleteRecursively()
            mkdirs()
        }
        val music = File(root, "Music").apply { mkdirs() }
        val documents = File(root, "Documents").apply { mkdirs() }
        val photos = File(root, "Photos").apply { mkdirs() }
        val videos = File(root, "Videos").apply { mkdirs() }
        File(music, "track.mp3").writeBytes(byteArrayOf(1, 2, 3))
        File(music, "legacy.aiff").writeBytes(byteArrayOf(1, 2, 3))
        File(documents, "report.pdf").writeBytes(byteArrayOf(4, 5, 6))
        File(photos, "cover.heic").writeBytes(byteArrayOf(7, 8, 9))
        File(videos, "clip.ts").writeBytes(byteArrayOf(10, 11, 12))
        File(videos, "legacy.wmv").writeBytes(byteArrayOf(10, 11, 12))

        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.requestScan(force = true)
            val first = awaitFinished(scanner)
            assertEquals("complete", first.getString("state"))
            assertEquals("manual", first.getString("scan_trigger"))
            scanner.configureAutomaticScanning(
                enabled = true,
                intervalMinutes = 60,
                scanOnStartup = false,
                scanOnStorageChange = false
            )
            assertEquals(6, first.getInt("new_files"))
            assertEquals(0, first.getInt("updated_files"))
            assertTrue(first.getLong("scanned_bytes") >= 18L)
            assertEquals(18L, first.getLong("indexed_bytes"))
            assertEquals(9L, first.getLong("media_bytes"))
            assertEquals(3, first.getInt("other_file_count"))
            assertTrue(first.getLong("last_successful_at") > 0L)
            assertEquals(first.getLong("last_completed_at"), first.getLong("last_attempt_finished_at"))
            assertTrue(first.getString("scan_run_id").isNotBlank())
            // The first scan result is an immutable snapshot captured before
            // automatic scanning was configured; assert the live settings instead.
            val enabledSettings = scanner.status().getJSONObject("automatic_scanning")
            assertTrue(enabledSettings.getBoolean("enabled"))
            assertEquals(60, enabledSettings.getInt("interval_minutes"))
            val disabledSettings = scanner.configureAutomaticScanning(
                enabled = false,
                intervalMinutes = 180,
                scanOnStartup = false,
                scanOnStorageChange = false
            )
            assertEquals(false, disabledSettings.getBoolean("enabled"))
            assertEquals(false, disabledSettings.getBoolean("scan_on_startup"))
            assertEquals(false, disabledSettings.getBoolean("scan_on_storage_change"))
            assertEquals(180, disabledSettings.getInt("interval_minutes"))
            assertEquals(1, first.getJSONArray("scan_history").length())
            assertEquals("complete", first.getJSONArray("volumes").getJSONObject(0).getString("state"))
            assertEquals(10, first.getInt("file_count"))
            assertEquals(4, first.getInt("directory_count"))
            assertEquals(6, first.getInt("regular_file_count"))
            assertEquals(1, first.getInt("music_count"))
            assertEquals(1, first.getInt("video_count"))
            assertEquals(1, first.getInt("photo_count"))
            assertEquals(5, first.getInt("scanned_directories"))
            assertEquals("track.mp3", scanner.media("music", "", 10, 0).single().name)
            assertEquals("clip.ts", scanner.media("video", "", 10, 0).single().name)
            assertEquals("audio/mpeg", scanner.media("music", "", 10, 0).single().mime)
            assertEquals("application/pdf", scanner.files("report.pdf", 10, 0).single().mime)

            SystemClock.sleep(5)
            scanner.requestScan(force = true)
            val second = awaitFinished(scanner, first.getLong("last_scan_started_at"))
            assertEquals("complete", second.getString("state"))
            assertEquals(10, second.getInt("unchanged_count"))
            assertEquals(0, second.getInt("indexed_count"))

            assertTrue(File(music, "track.mp3").delete())
            SystemClock.sleep(5)
            scanner.requestScan(force = true)
            val third = awaitFinished(scanner, second.getLong("last_scan_started_at"))
            assertEquals("complete", third.getString("state"))
            assertEquals(0, third.getInt("music_count"))
            assertEquals(9, third.getInt("file_count"))
        } finally {
            scanner.close()
            root.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }


    @Test
    fun resumesAnExistingVolumeCheckpointAndPrunesOnlyAfterCompletion() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val root = File(context.cacheDir, "media-index-resume").apply { deleteRecursively(); mkdirs() }
        val resumeDirectory = File(root, "Resume").apply { mkdirs() }
        File(resumeDirectory, "track.mp3").writeBytes(byteArrayOf(1, 2, 3))
        val database = MediaIndexDatabase(context)
        val rootId = root.canonicalPath
        val checkpoint = org.json.JSONObject()
            .put("pending", org.json.JSONArray().put("Resume"))
            .put("visited", org.json.JSONArray().put(rootId))
            .put("complete", true)
            .put("files_healthy", true)
            .put("media_healthy", true)
        try {
            database.upsertFiles(listOf(
                IndexedFile("internal", "deleted.txt", "deleted.txt", "file", 1, 1, "text/plain", null)
            ), "previous-scan")
            database.saveScanCheckpoint("internal", rootId, "resumed-scan-id", checkpoint.toString())
        } finally {
            database.close()
        }

        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            // A saved checkpoint must resume at host startup even when routine
            // automatic startup scans are disabled.
            scanner.ensureStarted()
            val result = awaitFinished(scanner)
            assertEquals("complete", result.getString("state"))
            assertEquals("track.mp3", scanner.media("music", "", 10, 0).single().name)
            assertTrue(scanner.files("deleted.txt", 10, 0).isEmpty())
            assertEquals(1, result.getInt("scanned_directories"))
            assertTrue(result.getInt("file_count") >= 2)
        } finally {
            scanner.close()
            root.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @Test
    fun resumesAnExternalSafCheckpointAfterHostStartup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val internalRoot = File(context.cacheDir, "media-index-saf-resume-internal").apply {
            deleteRecursively()
            mkdirs()
        }
        val externalRoot = File(context.cacheDir, "media-index-saf-resume-external").apply {
            deleteRecursively()
            mkdirs()
        }
        val music = File(externalRoot, "Music").apply { mkdirs() }
        File(music, "usb-track.mp3").writeBytes(byteArrayOf(1, 2, 3))
        val documentRoot = DocumentFile.fromFile(externalRoot)
        val database = MediaIndexDatabase(context)
        val checkpoint = org.json.JSONObject()
            .put("pending", org.json.JSONArray().put("Music"))
            .put("visited", org.json.JSONArray().put(documentRoot.uri.toString()))
            .put("complete", true)
            .put("files_healthy", true)
            .put("media_healthy", true)
        try {
            database.upsertFiles(listOf(
                IndexedFile("usb-test", "removed.txt", "removed.txt", "file", 1, 1, "text/plain", null)
            ), "previous-usb-scan")
            database.saveScanCheckpoint("usb-test", documentRoot.uri.toString(), "resumed-usb-scan", checkpoint.toString())
        } finally {
            database.close()
        }

        val scanner = MediaIndexScanner(
            context,
            { internalRoot },
            { listOf("usb-test" to DocumentFile.fromFile(externalRoot)) }
        )
        try {
            scanner.ensureStarted()
            val result = awaitFinished(scanner)
            assertEquals("complete", result.getString("state"))
            assertEquals("usb-track.mp3", scanner.media("music", "", 10, 0).single().name)
            assertTrue(scanner.files("removed.txt", 10, 0).isEmpty())
        } finally {
            scanner.close()
            internalRoot.deleteRecursively()
            externalRoot.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @Test
    fun scansDirectoriesDeeperThanTheFormerDepthLimit() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val root = File(context.cacheDir, "media-index-deep").apply { deleteRecursively(); mkdirs() }
        var deepest = root
        repeat(70) { deepest = File(deepest, "d").apply { mkdirs() } }
        File(deepest, "deep-track.mp3").writeBytes(byteArrayOf(1, 2, 3))
        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.requestScan(force = true)
            val result = awaitFinished(scanner)
            assertEquals("complete", result.getString("state"))
            assertEquals(71, result.getInt("scanned_directories"))
            assertEquals("deep-track.mp3", scanner.media("music", "", 10, 0).single().name)
        } finally {
            scanner.close()
            root.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @Test
    fun automaticallyContinuesAfterTenThousandDirectories() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val root = File(context.cacheDir, "media-index-batch").apply { deleteRecursively(); mkdirs() }
        repeat(10_001) { index -> File(root, "dir-$index").mkdirs() }
        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.requestScan(force = true)
            val result = awaitFinished(scanner, timeoutMs = 60_000L)
            assertEquals("complete", result.getString("state"))
            assertEquals(10_002, result.getInt("scanned_directories"))
            assertEquals(10_001, result.getInt("directory_count"))
        } finally {
            scanner.close()
            root.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @Test
    fun mediaQueriesRejectWrongExtensionsAndMismatchedMimeTypes() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        val database = MediaIndexDatabase(context)
        try {
            database.upsertMedia(listOf(
                IndexedFile("internal", "wrong-mime.mp3", "wrong-mime.mp3", "file", 1, 1, "video/mp4", "music"),
                IndexedFile("internal", "wrong-extension.flac", "wrong-extension.flac", "file", 1, 1, "audio/flac", "video"),
                IndexedFile("internal", "good.mp3", "good.mp3", "file", 1, 1, "audio/mpeg", "music"),
                IndexedFile("internal", "good.mp4", "good.mp4", "file", 1, 1, "video/mp4", "video")
            ), "test")
            assertEquals("good.mp3", database.queryMedia("music", "", 10, 0).single().name)
            assertEquals("good.mp4", database.queryMedia("video", "", 10, 0).single().name)
        } finally {
            database.close()
            context.deleteDatabase("pocketlink_index.db")
        }
    }

    private fun awaitFinished(
        scanner: MediaIndexScanner,
        afterStartedAt: Long = 0L,
        timeoutMs: Long = 15_000L
    ): org.json.JSONObject {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            val status = scanner.status()
            val scanRunId = status.optString("scan_run_id")
            val history = status.optJSONArray("scan_history")
            val reportPersisted = history != null &&
                history.length() > 0 &&
                history.optJSONObject(0)?.optString("run_id") == scanRunId
            if (status.optString("state") != "scanning" &&
                status.optLong("last_scan_started_at") > afterStartedAt &&
                reportPersisted
            ) {
                return status
            }
            SystemClock.sleep(25L)
        }
        throw AssertionError("Media index scan did not finish: ${scanner.status()}")
    }
}
