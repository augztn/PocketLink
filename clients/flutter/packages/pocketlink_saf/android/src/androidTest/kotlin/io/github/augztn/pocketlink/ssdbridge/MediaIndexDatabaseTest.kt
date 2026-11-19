package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaIndexDatabaseTest {
    @Test
    fun fileAndMediaIndexesPersistAndCanBePrunedIndependently() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase("pocketlink_index.db")
        val database = MediaIndexDatabase(context)
        try {
            val entries = listOf(
                IndexedFile("internal", "Music/song.mp3", "song.mp3", "file", 1234L, 100L, "audio/mpeg", "music"),
                IndexedFile("internal", "Pictures/photo.jpg", "photo.jpg", "file", 2345L, 200L, "image/jpeg", "photo"),
                IndexedFile("internal", "Documents", "Documents", "directory", 0L, 300L, "application/octet-stream", null)
            )
            database.upsertFiles(entries, "scan-a")
            database.upsertMedia(entries, "scan-a")

            assertEquals(3, database.counts()["files"])
            assertEquals(1, database.counts()["directories"])
            assertEquals(2, database.counts()["regular_files"])
            assertEquals(2, database.counts()["media"])
            assertEquals("song.mp3", database.queryMedia("music", "", 20, 0).single().name)
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
