package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.os.SystemClock
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
    fun scansInternalFilesAndPrunesDeletedEntriesAfterACompleteRefresh() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
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
        afterStartedAt: Long = 0L
    ): org.json.JSONObject {
        val deadline = SystemClock.elapsedRealtime() + 15_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            val status = scanner.status()
            if (status.optString("state") != "scanning" &&
                status.optLong("last_scan_started_at") > afterStartedAt
            ) {
                return status
            }
            SystemClock.sleep(25L)
        }
        throw AssertionError("Media index scan did not finish: ${scanner.status()}")
    }
}
