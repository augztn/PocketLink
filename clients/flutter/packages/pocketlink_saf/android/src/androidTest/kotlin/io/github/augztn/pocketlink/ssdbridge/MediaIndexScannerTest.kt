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
        File(music, "track.mp3").writeBytes(byteArrayOf(1, 2, 3))
        File(documents, "report.pdf").writeBytes(byteArrayOf(4, 5, 6))

        val scanner = MediaIndexScanner(context, { root }, { emptyList() })
        try {
            scanner.requestScan(force = true)
            val first = awaitFinished(scanner)
            assertEquals("complete", first.getString("state"))
            assertEquals(4, first.getInt("file_count"))
            assertEquals(2, first.getInt("directory_count"))
            assertEquals(2, first.getInt("regular_file_count"))
            assertEquals(1, first.getInt("music_count"))
            assertEquals(3, first.getInt("scanned_directories"))

            SystemClock.sleep(5)
            scanner.requestScan(force = true)
            val second = awaitFinished(scanner, first.getLong("last_scan_started_at"))
            assertEquals("complete", second.getString("state"))
            assertEquals(4, second.getInt("unchanged_count"))
            assertEquals(0, second.getInt("indexed_count"))

            assertTrue(File(music, "track.mp3").delete())
            SystemClock.sleep(5)
            scanner.requestScan(force = true)
            val third = awaitFinished(scanner, second.getLong("last_scan_started_at"))
            assertEquals("complete", third.getString("state"))
            assertEquals(0, third.getInt("music_count"))
            assertEquals(3, third.getInt("file_count"))
        } finally {
            scanner.close()
            root.deleteRecursively()
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
