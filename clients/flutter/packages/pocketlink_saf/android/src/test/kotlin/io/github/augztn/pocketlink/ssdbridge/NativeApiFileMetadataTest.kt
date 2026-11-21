package io.github.augztn.pocketlink.ssdbridge

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeApiFileMetadataTest {
    private val metadata = NativeApiFileMetadata()

    @Test
    fun validatesNamesWithoutAllowingHiddenOrPathSegments() {
        assertTrue(metadata.isValidName("Music"))
        assertTrue(metadata.isValidName("track 01.flac"))
        assertFalse(metadata.isValidName(""))
        assertFalse(metadata.isValidName("."))
        assertFalse(metadata.isValidName(".."))
        assertFalse(metadata.isValidName(".hidden"))
        assertFalse(metadata.isValidName("folder/file"))
        assertFalse(metadata.isValidName("folder\\file"))
        assertFalse(metadata.isValidName("bad\u0001name"))
    }

    @Test
    fun formatsDatesInStableUtcIso8601Format() {
        assertEquals("1970-01-01T00:00:00.000Z", metadata.formatDate(0L))
        assertEquals("1970-01-01T00:00:01.234Z", metadata.formatDate(1_234L))
    }

    @Test
    fun serializesFileMetadataWithoutChangingTheApiShape() {
        val directory = createTempDir(prefix = "pocketlink-metadata-")
        try {
            val file = File(directory, "track.mp3").apply { writeText("audio") }
            val json = metadata.fileJson(file)

            assertEquals("track.mp3", json.getString("name"))
            assertEquals("file", json.getString("type"))
            assertEquals(5L, json.getLong("size"))
            assertTrue(json.getString("modified").endsWith("Z"))
        } finally {
            directory.deleteRecursively()
        }
    }
}
