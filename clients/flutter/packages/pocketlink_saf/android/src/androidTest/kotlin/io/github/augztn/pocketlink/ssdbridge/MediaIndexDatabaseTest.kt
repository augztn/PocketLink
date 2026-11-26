package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class MediaIndexDatabaseTest {
    @Test
    fun pathSnapshotsLoadOnlyRequestedRowsAndDetectDescendantsInSql() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        val database = MediaIndexDatabase(context)
        try {
            val entries = (0 until 2_000).map { index ->
                IndexedFile(
                    "internal",
                    "Library/track-$index.mp3",
                    "track-$index.mp3",
                    "file",
                    index.toLong(),
                    index.toLong(),
                    "audio/mpeg",
                    "music"
                )
            }
            database.upsertFiles(entries, "scan")
            database.upsertMedia(entries, "scan")

            val requested = listOf("Library/track-17.mp3", "Library/track-999.mp3")
            val files = database.fileSnapshot("internal", requested)
            val media = database.mediaSnapshot("internal", requested)

            assertEquals(2, files.size)
            assertEquals(2, media.size)
            assertEquals(17L, files["Library/track-17.mp3"]?.size)
            assertEquals("music", media["Library/track-999.mp3"]?.category)
            assertTrue(database.hasIndexedDescendants("internal", "Library"))
            assertTrue(database.hasIndexedDescendants("internal", ""))
            assertTrue(!database.hasIndexedDescendants("internal", "Missing"))
            assertTrue(!database.hasIndexedDescendants("internal", "Library/track-17.mp3"))
        } finally {
            database.close()
            context.deleteDatabase("pocketlink_index.db")
        }
    }

    @Test
    fun statsSnapshotIsStableAndReadOnlyAcrossSubsequentWrites() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        val database = MediaIndexDatabase(context)
        try {
            val snapshot = database.statsSnapshot()
            database.upsertFiles(
                listOf(IndexedFile("internal", "note.txt", "note.txt", "file", 42L, 1L,
                    "text/plain", null)),
                "scan"
            )

            assertEquals(0, snapshot.counts["files"])
            assertEquals(0L, snapshot.sizes["indexed_bytes"])
            assertEquals(1, database.statsSnapshot().counts["files"])
            assertEquals(42L, database.statsSnapshot().sizes["indexed_bytes"])

            try {
                @Suppress("UNCHECKED_CAST")
                (snapshot.counts as MutableMap<String, Int>)["files"] = 99
                throw AssertionError("Stats snapshot counts must be immutable")
            } catch (_: UnsupportedOperationException) {
                // Expected: callers cannot mutate a published snapshot.
            }
        } finally {
            database.close()
            context.deleteDatabase("pocketlink_index.db")
        }
    }

    @Test
    fun aggregateStatsNeverMixCountsAndBytesDuringConcurrentWrites() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        val database = MediaIndexDatabase(context)
        val start = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        val writer = Thread {
            try {
                start.await()
                repeat(40) { index ->
                    database.upsertFiles(
                        listOf(IndexedFile("internal", "file-$index.txt", "file-$index.txt",
                            "file", 42L, index.toLong(), "text/plain", null)),
                        "scan"
                    )
                }
            } catch (error: Throwable) {
                failure.compareAndSet(null, error)
            }
        }
        val reader = Thread {
            try {
                start.await()
                repeat(80) {
                    val snapshot = database.statsSnapshot()
                    val expectedBytes = (snapshot.counts["files"] ?: 0).toLong() * 42L
                    assertEquals(expectedBytes, snapshot.sizes["indexed_bytes"])
                }
            } catch (error: Throwable) {
                failure.compareAndSet(null, error)
            }
        }

        try {
            writer.start()
            reader.start()
            start.countDown()
            writer.join()
            reader.join()
            failure.get()?.let { throw AssertionError("Concurrent stats snapshot failed", it) }
            assertEquals(40, database.statsSnapshot().counts["files"])
        } finally {
            database.close()
            context.deleteDatabase("pocketlink_index.db")
        }
    }

    @Test
    fun fileAndMediaIndexesPersistAndCanBePrunedIndependently() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        val database = MediaIndexDatabase(context)
        try {
            val entries = listOf(
                IndexedFile(
                    "internal", "Music/song.mp3", "song.mp3", "file", 1234L, 100L,
                    "audio/mpeg", "music", "Embedded Title", "Embedded Artist",
                    "Embedded Album", 187000L, true
                ),
                IndexedFile("internal", "Pictures/photo.jpg", "photo.jpg", "file", 2345L, 200L, "image/jpeg", "photo"),
                IndexedFile("internal", "Documents", "Documents", "directory", 0L, 300L, "application/octet-stream", null)
            )
            database.upsertFiles(entries, "scan-a")
            database.upsertMedia(entries, "scan-a")

            assertEquals(3, database.counts()["files"])
            assertEquals(1, database.counts()["directories"])
            assertEquals(2, database.counts()["regular_files"])
            assertEquals(2, database.counts()["media"])
            val indexedSong = database.queryMedia("music", "", 20, 0).single()
            assertEquals("song.mp3", indexedSong.name)
            assertEquals("Embedded Title", indexedSong.title)
            assertEquals("Embedded Artist", indexedSong.artist)
            assertEquals("Embedded Album", indexedSong.album)
            assertEquals(187000L, indexedSong.durationMs)
            assertTrue(indexedSong.metadataScanned)
            assertEquals("photo.jpg", database.queryMedia("photo", "", 20, 0).single().name)
            assertTrue(database.searchFiles("Documents", 20, 0).any { it.type == "directory" })

            database.finishMediaSource("internal", "scan-b")
            assertEquals(3, database.counts()["files"])
            assertEquals(0, database.counts()["media"])
        } finally {
            database.close()
            context.deleteDatabase("pocketlink_index.db")
        }
    }
}
