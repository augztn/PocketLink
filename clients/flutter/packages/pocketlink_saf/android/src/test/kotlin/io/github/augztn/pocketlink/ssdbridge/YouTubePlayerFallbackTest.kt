package io.github.augztn.pocketlink.ssdbridge

import okhttp3.OkHttpClient
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class YouTubePlayerFallbackTest {
    private val resolver = YouTubePlayerFallback(OkHttpClient())

    @Test
    fun prefersDirectOpusAudioAndRetainsProgressiveFallback() {
        val player = JSONObject(
            """
            {
              "playabilityStatus": {"status": "OK"},
              "streamingData": {
                "adaptiveFormats": [
                  {
                    "itag": 140,
                    "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                    "bitrate": 128000,
                    "url": "https://r1.googlevideo.com/videoplayback?itag=140"
                  },
                  {
                    "itag": 251,
                    "mimeType": "audio/webm; codecs=\"opus\"",
                    "averageBitrate": 160000,
                    "url": "https://r2.googlevideo.com/videoplayback?itag=251"
                  },
                  {
                    "itag": 250,
                    "mimeType": "audio/webm",
                    "url": "https://untrusted.example/audio"
                  }
                ],
                "formats": [
                  {
                    "itag": 18,
                    "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
                    "url": "https://r3.googlevideo.com/videoplayback?itag=18"
                  }
                ]
              }
            }
            """.trimIndent()
        )

        val streams = resolver.parseStreams(player)

        assertEquals(3, streams.size)
        assertEquals(251, streams[0].itag)
        assertEquals("audio/webm", streams[0].mimeType)
        assertEquals(140, streams[1].itag)
        assertEquals(18, streams[2].itag)
        assertTrue(streams.all { it.url.startsWith("https://") })
    }

    @Test
    fun ignoresCipherOnlyDrmAndNonPlayableResponses() {
        val player = JSONObject(
            """
            {
              "playabilityStatus": {"status": "LOGIN_REQUIRED"},
              "streamingData": {
                "adaptiveFormats": [
                  {
                    "itag": 251,
                    "mimeType": "audio/webm",
                    "signatureCipher": "s=encrypted"
                  },
                  {
                    "itag": 140,
                    "mimeType": "audio/mp4",
                    "isDrm": true,
                    "url": "https://r1.googlevideo.com/videoplayback?itag=140"
                  }
                ]
              }
            }
            """.trimIndent()
        )

        assertTrue(resolver.parseStreams(player).isEmpty())
    }
}
