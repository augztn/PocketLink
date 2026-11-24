package io.github.augztn.pocketlink.ssdbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaFileClassifierTest {
    @Test
    fun classifiesAudioAndVideoOnlyWhenMimeMatchesOrIsGeneric() {
        assertEquals("music", MediaFileClassifier.categoryFor("track.MP3", "audio/mpeg; charset=binary"))
        assertEquals("music", MediaFileClassifier.categoryFor("track.flac", "application/octet-stream"))
        assertNull(MediaFileClassifier.categoryFor("track.mp3", "video/mp4"))
        assertEquals("video", MediaFileClassifier.categoryFor("clip.mkv", "video/x-matroska"))
        assertNull(MediaFileClassifier.categoryFor("clip.mp4", "audio/mp4"))
    }

    @Test
    fun classifiesAdditionalLosslessAudioFormats() {
        listOf("alac", "aiff", "aif", "wv", "ape", "dsf", "dff").forEach { extension ->
            assertEquals("music", MediaFileClassifier.categoryFor("track.$extension", "application/octet-stream"))
        }
        assertEquals("music", MediaFileClassifier.categoryFor("track.aiff", "audio/aiff"))
    }

    @Test
    fun classifiesPhotoAndCameraRawExtensionsIndependentlyOfMime() {
        assertEquals("photo", MediaFileClassifier.categoryFor("cover.heic", "image/heic"))
        assertEquals("photo", MediaFileClassifier.categoryFor("camera.dng", "application/octet-stream"))
        assertNull(MediaFileClassifier.categoryFor("document.pdf", "application/pdf"))
    }

    @Test
    fun mapsKnownExtensionsWithoutPlatformFallback() {
        assertEquals("audio/mpeg", MediaFileClassifier.mimeForName("track.MP3"))
        assertEquals("video/mp2t", MediaFileClassifier.mimeForName("clip.ts"))
        assertEquals("application/pdf", MediaFileClassifier.mimeForName("report.pdf"))
    }
}
