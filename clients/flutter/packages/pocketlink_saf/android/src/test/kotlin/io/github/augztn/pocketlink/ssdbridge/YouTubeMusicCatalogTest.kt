package io.github.augztn.pocketlink.ssdbridge

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class YouTubeMusicCatalogTest {
    private val catalog = YouTubeMusicCatalog()

    @Test
    fun requestContextUsesSelectedRegionAndDeviceTimezone() {
        val context = catalog.buildClientContext("JP")
        assertEquals("JP", context.optString("gl"))
        assertTrue(context.optInt("utcOffsetMinutes") in -720..840)
    }

    @Test
    fun invalidRegionFallsBackToIndia() {
        val context = catalog.buildClientContext("not-a-country")
        assertEquals("IN", context.optString("gl"))
    }

    @Test
    fun parsesMusicResponsiveListItemsAndMetadata() {
        val json = JSONObject(
            """
            {
              "contents": {
                "musicShelfRenderer": {
                  "contents": [{
                    "musicResponsiveListItemRenderer": {
                      "playlistItemData": {"videoId": "abcdefghijk"},
                      "flexColumns": [
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Mazha"}]}}},
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Sithara"}]}}},
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "4:12"}}}
                      ],
                      "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
                        {"url": "https://example.com/low.jpg"},
                        {"url": "https://example.com/high.jpg"}
                      ]}}}
                    }
                  }]
                }
              }
            }
            """.trimIndent()
        )

        val tracks = catalog.parseTracks(json, 20)

        assertEquals(1, tracks.size)
        assertEquals("abcdefghijk", tracks.single()["videoId"])
        assertEquals("Mazha", tracks.single()["title"])
        assertEquals("Sithara", tracks.single()["artist"])
        assertEquals("4:12", tracks.single()["durationText"])
        assertEquals("https://example.com/high.jpg", tracks.single()["thumbnailUrl"])
    }

    @Test
    fun ignoresMalformedAndDuplicateVideoItems() {
        val json = JSONObject(
            """
            {
              "items": [
                {"musicResponsiveListItemRenderer": {
                  "playlistItemData": {"videoId": "abcdefghijk"},
                  "flexColumns": [
                    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "Track"}}}
                  ]
                }},
                {"musicResponsiveListItemRenderer": {
                  "playlistItemData": {"videoId": "abcdefghijk"},
                  "flexColumns": [
                    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "Track"}}}
                  ]
                }},
                {"musicResponsiveListItemRenderer": {
                  "playlistItemData": {"videoId": "bad id"},
                  "flexColumns": [
                    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "Invalid"}}}
                  ]
                }}
              ]
            }
            """.trimIndent()
        )

        val tracks = catalog.parseTracks(json, 20)

        assertEquals(1, tracks.size)
        assertEquals("Track", tracks.single()["title"])
    }

    @Test
    fun enforcesRequestedResultLimit() {
        val items = (1..3).joinToString(",") { index ->
            """{"musicResponsiveListItemRenderer":{
              "playlistItemData":{"videoId":"video00000$index"},
              "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"simpleText":"Track $index"}}}]
            }}"""
        }
        val tracks = catalog.parseTracks(JSONObject("""{"items":[$items]}"""), 2)
        assertEquals(2, tracks.size)
        assertTrue(tracks.all { (it["title"] as String).startsWith("Track") })
    }
}
