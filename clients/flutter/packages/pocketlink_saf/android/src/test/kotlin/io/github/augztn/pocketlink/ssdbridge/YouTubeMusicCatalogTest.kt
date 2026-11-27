package io.github.augztn.pocketlink.ssdbridge

import okio.Buffer
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
    fun innerTubeBrowseRequestUsesWebRemixIdentityHeadersAndContext() {
        val request = catalog.buildRequest(
            "browse",
            JSONObject().put("browseId", "FEmusic_moods_and_genres"),
            "IN"
        )

        assertEquals("1", request.header("X-Goog-Api-Format-Version"))
        assertEquals("67", request.header("X-YouTube-Client-Name"))
        assertEquals("1.20260707.12.00", request.header("X-YouTube-Client-Version"))
        assertTrue(request.header("User-Agent")!!.contains("Firefox/140.0"))
        assertEquals("https://music.youtube.com", request.header("Origin"))

        val buffer = Buffer()
        request.body!!.writeTo(buffer)
        val body = JSONObject(buffer.readUtf8())
        val client = body.getJSONObject("context").getJSONObject("client")
        assertEquals("WEB_REMIX", client.optString("clientName"))
        assertEquals("1.20260707.12.00", client.optString("clientVersion"))
        assertEquals("FEmusic_moods_and_genres", body.optString("browseId"))
        assertEquals("IN", client.optString("gl"))
    }

    @Test
    fun parsesDynamicMoodAndGenreSections() {
        val json = JSONObject(
            """
            {
              "contents": {"sectionListRenderer": {"contents": [
                {"gridRenderer": {
                  "header": {"gridHeaderRenderer": {"title": {"runs": [{"text": "Moods & moments"}]}}},
                  "items": [
                    {"musicNavigationButtonRenderer": {
                      "buttonText": {"runs": [{"text": "Chill"}]},
                      "solid": {"leftStripeColor": 4281545523},
                      "clickCommand": {"browseEndpoint": {"browseId": "FEmusic_mood_chill", "params": "test-params"}}
                    }}
                  ]
                }}
              ]}}
            }
            """.trimIndent()
        )

        val sections = catalog.parseMoodAndGenres(json)
        assertEquals(1, sections.size)
        assertEquals("Moods & moments", sections.single()["title"])
        @Suppress("UNCHECKED_CAST")
        val item = (sections.single()["items"] as List<Map<String, Any>>).single()
        assertEquals("Chill", item["title"])
        assertEquals("FEmusic_mood_chill", item["browseId"])
        assertEquals("test-params", item["params"])
        assertEquals(4281545523L, item["stripeColor"])
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
    fun selectsLargestArtworkAndUpgradesItsResolution() {
        val json = JSONObject(
            """
            {
              "items": [{
                "musicTwoRowItemRenderer": {
                  "videoId": "abcdefghijk",
                  "title": {"simpleText": "Artwork test"},
                  "thumbnail": {"thumbnails": [
                    {"url": "https://lh3.googleusercontent.com/art=w144-h144-l90-rj", "width": 144, "height": 144},
                    {"url": "https://lh3.googleusercontent.com/art=w544-h544-l90-rj", "width": 544, "height": 544}
                  ]}
                }
              }]
            }
            """.trimIndent()
        )

        val track = catalog.parseTracks(json, 1).single()

        assertEquals(
            "https://lh3.googleusercontent.com/art=w1200-h1200-l90-rj",
            track["thumbnailUrl"]
        )
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

    @Test
    fun parsesDynamicHomeShelvesAndRemovesRepeatedTracksAcrossSections() {
        val json = JSONObject(
            """
            {
              "contents": {"sectionListRenderer": {"contents": [
                {"musicCarouselShelfRenderer": {
                  "header": {"musicCarouselShelfBasicHeaderRenderer": {
                    "title": {"simpleText": "Trending now"}
                  }},
                  "contents": [
                    {"musicTwoRowItemRenderer": {
                      "videoId": "abcdefghijk",
                      "title": {"simpleText": "First track"},
                      "subtitle": {"simpleText": "First artist"}
                    }}
                  ]
                }},
                {"musicShelfRenderer": {
                  "header": {"musicShelfHeaderRenderer": {
                    "title": {"simpleText": "New releases"}
                  }},
                  "contents": [
                    {"musicResponsiveListItemRenderer": {
                      "playlistItemData": {"videoId": "abcdefghijk"},
                      "flexColumns": [
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "Duplicate"}}}
                      ]
                    }},
                    {"musicResponsiveListItemRenderer": {
                      "playlistItemData": {"videoId": "lmnopqrstuv"},
                      "flexColumns": [
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "Second track"}}},
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"simpleText": "Second artist"}}}
                      ]
                    }}
                  ]
                }}
              ]}},
              "continuations": [{"nextContinuationData": {"continuation": "next-page-token"}}]
            }
            """.trimIndent()
        )

        val shelves = catalog.parseHomeShelves(json, 20)

        assertEquals(2, shelves.size)
        assertEquals("Trending now", shelves[0]["title"])
        assertEquals("New releases", shelves[1]["title"])
        @Suppress("UNCHECKED_CAST")
        val firstTracks = shelves[0]["tracks"] as List<Map<String, Any>>
        @Suppress("UNCHECKED_CAST")
        val secondTracks = shelves[1]["tracks"] as List<Map<String, Any>>
        assertEquals(listOf("abcdefghijk"), firstTracks.map { it["videoId"] })
        assertEquals(listOf("lmnopqrstuv"), secondTracks.map { it["videoId"] })
        assertEquals("next-page-token", catalog.findContinuationToken(json))
    }

    @Test
    fun parsesPlaylistAndArtistCardsWithoutRequiringVideoIds() {
        val json = JSONObject(
            """
            {
              "contents": [
                {"musicTwoRowItemRenderer": {
                  "title": {"simpleText": "Sunday songs"},
                  "subtitle": {"simpleText": "Community playlist"},
                  "playlistId": "PL1234567890",
                  "navigationEndpoint": {
                    "browseEndpoint": {"browseId": "VLPL1234567890", "params": "playlist-params"}
                  },
                  "thumbnail": {"thumbnails": [
                    {"url": "https://example.com/playlist.jpg", "width": 544, "height": 544}
                  ]}
                }},
                {"musicTwoRowItemRenderer": {
                  "title": {"simpleText": "Anirudh Ravichander"},
                  "subtitle": {"simpleText": "Artist"},
                  "navigationEndpoint": {
                    "browseEndpoint": {"browseId": "UCabcdefghijk"}
                  },
                  "thumbnail": {"thumbnails": [
                    {"url": "https://example.com/artist.jpg", "width": 544, "height": 544}
                  ]}
                }}
              ]
            }
            """.trimIndent()
        )

        val items = catalog.parseHomeItems(json, 20)
        val shelf = JSONObject()
            .put(
                "header",
                JSONObject().put(
                    "musicCarouselShelfBasicHeaderRenderer",
                    JSONObject().put("title", JSONObject().put("simpleText", "From the community"))
                )
            )
            .put("contents", json.getJSONArray("contents"))
        val root = JSONObject().put(
            "contents",
            JSONObject().put("musicCarouselShelfRenderer", shelf)
        )
        val shelves = catalog.parseHomeShelves(root, 20)

        assertEquals(1, shelves.size)
        assertEquals("From the community", shelves.single()["title"])
        @Suppress("UNCHECKED_CAST")
        val shelfItems = shelves.single()["items"] as List<Map<String, Any>>
        assertEquals(2, shelfItems.size)
        @Suppress("UNCHECKED_CAST")
        val shelfTracks = shelves.single()["tracks"] as List<Map<String, Any>>
        assertTrue(shelfTracks.isEmpty())
        assertEquals(2, items.size)
        assertEquals("playlist", items[0]["type"])
        assertEquals("Sunday songs", items[0]["title"])
        assertEquals("VLPL1234567890", items[0]["browseId"])
        assertEquals("playlist-params", items[0]["params"])
        assertEquals("artist", items[1]["type"])
        assertEquals("UCabcdefghijk", items[1]["browseId"])
    }

}
