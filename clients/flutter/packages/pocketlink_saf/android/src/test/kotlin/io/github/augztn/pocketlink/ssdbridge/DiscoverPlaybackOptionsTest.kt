package io.github.augztn.pocketlink.ssdbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DiscoverPlaybackOptionsTest {
    private data class Format(val bitrate: Long, val opus: Boolean)

    @Test
    fun bestAvailablePreservesOpusPreferenceAndHighestBitrate() {
        val formats = listOf(
            Format(256_000, false),
            Format(128_000, true),
            Format(160_000, true)
        )
        val selected = DiscoverPlaybackOptions.selectAudioFormat(
            formats, "best_available", { it.bitrate }, { it.opus }
        )
        assertEquals(160_000L, selected?.bitrate)
    }

    @Test
    fun balancedSelectsHighestFormatWithinTarget() {
        val formats = listOf(
            Format(256_000, true),
            Format(128_000, false),
            Format(160_000, true),
            Format(96_000, true)
        )
        val selected = DiscoverPlaybackOptions.selectAudioFormat(
            formats, "balanced", { it.bitrate }, { it.opus }
        )
        assertEquals(160_000L, selected?.bitrate)
    }

    @Test
    fun dataSaverSelectsHighestFormatWithinTarget() {
        val formats = listOf(
            Format(160_000, true),
            Format(96_000, false),
            Format(64_000, true)
        )
        val selected = DiscoverPlaybackOptions.selectAudioFormat(
            formats, "data_saver", { it.bitrate }, { it.opus }
        )
        assertEquals(96_000L, selected?.bitrate)
    }

    @Test
    fun qualityFallsBackToClosestAvailableWhenNoFormatMeetsTarget() {
        val formats = listOf(Format(128_000, true), Format(192_000, false))
        val selected = DiscoverPlaybackOptions.selectAudioFormat(
            formats, "data_saver", { it.bitrate }, { it.opus }
        )
        assertEquals(128_000L, selected?.bitrate)
        assertEquals(
            "No available stream met the requested bitrate target; the closest available stream was selected.",
            DiscoverPlaybackOptions.qualityFallbackReason("data_saver", selected!!.bitrate)
        )
    }

    @Test
    fun reportsWhenTheStreamDoesNotExposeBitrate() {
        assertEquals(
            "The selected stream did not report a bitrate.",
            DiscoverPlaybackOptions.qualityFallbackReason("balanced", 0)
        )
        assertNull(DiscoverPlaybackOptions.qualityFallbackReason("best_available", 0))
    }

    @Test
    fun resolverProfilesHaveDistinctOrdersAndAutomaticLearnsLastSuccess() {
        assertEquals(
            listOf("NEWPIPE", "PLAYER_API"),
            DiscoverPlaybackOptions.resolverOrder("automatic", null)
        )
        assertEquals(
            listOf("PLAYER_API", "NEWPIPE"),
            DiscoverPlaybackOptions.resolverOrder("automatic", "PLAYER_API")
        )
        assertEquals(
            listOf("NEWPIPE", "PLAYER_API"),
            DiscoverPlaybackOptions.resolverOrder("newpipe_first", "PLAYER_API")
        )
        assertEquals(
            listOf("PLAYER_API", "NEWPIPE"),
            DiscoverPlaybackOptions.resolverOrder("player_api_first", "NEWPIPE")
        )
    }

    @Test
    fun normalizesRegionAndUnsupportedOptionsSafely() {
        assertEquals("IN", DiscoverPlaybackOptions.normalizeRegion(null))
        assertEquals("IN", DiscoverPlaybackOptions.normalizeRegion("invalid"))
        assertEquals("JP", DiscoverPlaybackOptions.normalizeRegion(" jp "))
        assertEquals("best_available", DiscoverPlaybackOptions.normalizeQuality("unknown"))
        assertEquals("automatic", DiscoverPlaybackOptions.normalizeResolverProfile("unknown"))
    }
}
