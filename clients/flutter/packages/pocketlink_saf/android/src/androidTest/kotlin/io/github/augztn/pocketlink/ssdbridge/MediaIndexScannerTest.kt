package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.database.sqlite.SQLiteDatabase
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
    fun retriesAnUnreadableDirectoryWithoutPruningUntilTheRetryCompletes() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val root = File(context.cacheDir, "media-index-retry").apply {
            deleteRecursively()
            mkdirs()
        }
        val blocked = File(root, "Blocked").apply { mkdirs() }
        File(blocked, "available-again.mp3").writeBytes(byteArrayOf(1, 2, 3))
        val database = MediaIndexDatabase(context)
        try {
            val stale = IndexedFile(
                "internal", "Blocked/old-track.mp3", "old-track.mp3",
                "file", 3, 1, "audio/mpeg", "music"
            )
            database.upsertFiles(listOf(stale), "previous-scan")
            database.upsertMedia(listOf(stale), "previous-scan")
        } finally {
            database.close()
        }

        blocked.setReadable(false, false)
        assertTrue("Test directory must be unreadable", !blocked.canRead())
        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.requestScan(force = true)
            val partial = awaitFinished(scanner)
            assertEquals("partial", partial.getString("state"))
            assertEquals(1, partial.getInt("music_count"))
            assertEquals("old-track.mp3", scanner.media("music", "", 10, 0).single().name)
            val checkpointDatabase = MediaIndexDatabase(context)
            try {
                assertTrue("Unreadable directory must remain in the durable scan checkpoint",
                    checkpointDatabase.hasScanCheckpoints())
            } finally {
                checkpointDatabase.close()
            }

            assertTrue(blocked.setReadable(true, false))
            SystemClock.sleep(5)
            scanner.retryFailedScan()
            val completed = awaitFinished(scanner, partial.getLong("last_scan_started_at"))
            assertEquals("complete", completed.getString("state"))
            assertEquals("available-again.mp3", scanner.media("music", "", 10, 0).single().name)
            assertTrue(scanner.files("old-track.mp3", 10, 0).isEmpty())
            val completedDatabase = MediaIndexDatabase(context)
            try {
                assertTrue("Checkpoint should clear only after the retry completes",
                    !completedDatabase.hasScanCheckpoints())
            } finally {
                completedDatabase.close()
            }
        } finally {
            blocked.setReadable(true, false)
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
            // Model the first batch having indexed the root and queued Resume.
            // Its directory row already belongs to the resumed scan and must survive pruning.
            database.upsertFiles(listOf(
                IndexedFile("internal", "deleted.txt", "deleted.txt", "file", 1, 1, "text/plain", null)
            ), "previous-scan")
            database.upsertFiles(listOf(
                IndexedFile("internal", "Resume", "Resume", "directory", 0, 1, "application/octet-stream", null)
            ), "resumed-scan-id")
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
            .putString("last_attempt_trigger", "manual")
            .putLong("last_attempt_started_at", 1L)
            .putLong("last_attempt_finished_at", 1L)
            .putString("scan_history", org.json.JSONArray().put(
                org.json.JSONObject()
                    .put("run_id", "previous-run")
                    .put("started_at", 1L)
                    .put("completed_at", 1L)
                    .put("state", "partial")
                    .put("volumes", org.json.JSONArray().put(
                        org.json.JSONObject().put("volume", "usb-test").put("state", "complete")
                    ))
            ).toString())
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
            scanner.onStorageChanged(connected = false, volumeId = "usb-test")
            scanner.ensureStarted()
            val disconnected = awaitFinished(scanner)
            assertEquals("partial", disconnected.getString("state"))

            // Reconnection must resume the saved SAF traversal despite routine
            // automatic storage-change scans being disabled.
            scanner.onStorageChanged(connected = true, volumeId = "usb-test")
            val result = awaitFinished(scanner, disconnected.getLong("last_scan_started_at"))
            assertEquals("complete", result.getString("state"))
            assertEquals(2, result.getInt("scanned_directories"))
            assertEquals(1, result.getInt("scanned"))
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
    fun indexesHiddenFilesAndDirectories() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()
        val root = File(context.cacheDir, "media-index-hidden").apply {
            deleteRecursively()
            mkdirs()
        }
        File(root, ".hidden.mp3").writeBytes(byteArrayOf(1, 2, 3))
        val hiddenDirectory = File(root, ".hidden-directory").apply { mkdirs() }
        File(hiddenDirectory, ".nested-hidden.mp3").writeBytes(byteArrayOf(4, 5, 6))
        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.requestScan(force = true)
            val result = awaitFinished(scanner)
            assertEquals("complete", result.getString("state"))
            assertEquals(
                setOf(".hidden.mp3", ".nested-hidden.mp3"),
                scanner.media("music", "", 10, 0).map { it.name }.toSet()
            )
        } finally {
            scanner.close()
            root.deleteRecursively()
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


    @Test
    fun migratesVersionTwoCheckpointAndPreservesIndexedRows() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit()
            .clear()
            .putBoolean("automatic_scanning_enabled", false)
            .putBoolean("scan_on_startup", false)
            .putBoolean("scan_on_storage_change", false)
            .commit()

        val root = File(context.cacheDir, "media-index-v2-migration").apply {
            deleteRecursively()
            mkdirs()
        }
        val resumeDirectory = File(root, "Resume").apply { mkdirs() }
        File(resumeDirectory, "migrated-track.mp3").writeBytes(byteArrayOf(1, 2, 3))
        val scanId = "legacy-v2-scan"
        val databaseFile = context.getDatabasePath("pocketlink_index.db")
        databaseFile.parentFile?.mkdirs()
        val legacy = SQLiteDatabase.openOrCreateDatabase(databaseFile, null)
        try {
            legacy.execSQL("""
                CREATE TABLE files (
                    volume TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL,
                    type TEXT NOT NULL, size INTEGER NOT NULL, modified INTEGER NOT NULL,
                    mime TEXT NOT NULL, scan_id TEXT NOT NULL,
                    PRIMARY KEY(volume, path)
                )
            """.trimIndent())
            legacy.execSQL("""
                CREATE TABLE media (
                    volume TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL,
                    category TEXT NOT NULL, size INTEGER NOT NULL, modified INTEGER NOT NULL,
                    mime TEXT NOT NULL, scan_id TEXT NOT NULL,
                    PRIMARY KEY(volume, path)
                )
            """.trimIndent())
            legacy.execSQL("""
                CREATE TABLE scan_checkpoints (
                    volume TEXT PRIMARY KEY NOT NULL,
                    root_id TEXT NOT NULL,
                    scan_id TEXT NOT NULL,
                    state TEXT NOT NULL
                )
            """.trimIndent())
            legacy.execSQL(
                "INSERT INTO files VALUES(?,?,?,?,?,?,?,?)",
                arrayOf("internal", "Resume", "Resume", "directory", 0, 1,
                    "application/octet-stream", scanId)
            )
            legacy.execSQL(
                "INSERT INTO files VALUES(?,?,?,?,?,?,?,?)",
                arrayOf("internal", "stale.txt", "stale.txt", "file", 1, 1,
                    "text/plain", "older-scan")
            )
            legacy.execSQL(
                "INSERT INTO media VALUES(?,?,?,?,?,?,?,?)",
                arrayOf("internal", "stale.mp3", "stale.mp3", "music", 1, 1,
                    "audio/mpeg", "older-scan")
            )
            val checkpoint = org.json.JSONObject()
                .put("pending", org.json.JSONArray().put("Resume"))
                .put("visited", org.json.JSONArray().put(root.canonicalPath))
                .put("complete", true)
                .put("files_healthy", true)
                .put("media_healthy", true)
            legacy.execSQL(
                "INSERT INTO scan_checkpoints(volume,root_id,scan_id,state) VALUES(?,?,?,?)",
                arrayOf("internal", root.canonicalPath, scanId, checkpoint.toString())
            )
            legacy.version = 2
        } finally {
            legacy.close()
        }

        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.ensureStarted()
            val result = awaitFinished(scanner)
            assertEquals("complete", result.getString("state"))
            assertEquals("migrated-track.mp3", scanner.media("music", "", 10, 0).single().name)
            assertTrue(scanner.files("stale.txt", 10, 0).isEmpty())
            val migrated = MediaIndexDatabase(context)
            try {
                assertTrue("Version-two checkpoint must be cleared after its resumed scan completes",
                    !migrated.hasScanCheckpoints())
                assertTrue(migrated.fileSnapshot("internal").containsKey("Resume/migrated-track.mp3"))
            } finally {
                migrated.close()
            }
        } finally {
            scanner.close()
            root.deleteRecursively()
            context.deleteDatabase("pocketlink_index.db")
            context.getSharedPreferences("media-index-report", Context.MODE_PRIVATE).edit().clear().commit()
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
