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
