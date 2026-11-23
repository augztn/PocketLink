package io.github.augztn.pocketlink.ssdbridge

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

internal data class YouTubePlayerStream(
    val url: String,
    val mimeType: String,
    val bitrateBps: Long,
    val userAgent: String,
    val codec: String,
    val itag: Int,
    val client: String,
    val audioOnly: Boolean
)

/**
 * Secondary resolver for cases where NewPipeExtractor cannot expose a direct stream.
 * Only accepts direct HTTPS googlevideo URLs. Cipher-only formats remain NewPipe's job.
 */
internal class YouTubePlayerFallback(client: OkHttpClient) {
    private val http = client.newBuilder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .callTimeout(10, TimeUnit.SECONDS)
        .build()

    fun resolve(videoId: String, regionCode: String, quality: String): YouTubePlayerStream? {
        require(VIDEO_ID.matches(videoId)) { "Invalid YouTube video ID." }
        var progressiveFallback: YouTubePlayerStream? = null
        for (profile in CLIENTS) {
            val response = runCatching {
                requestPlayer(videoId, profile, regionCode)
            }.getOrNull() ?: continue
            val streams = parseStreams(response, profile)
            val audio = streams.filter { it.audioOnly }
            val selected = DiscoverPlaybackOptions.selectAudioFormat(
                audio,
                quality,
                { it.bitrateBps },
                { isOpus(it) }
            )
            if (selected != null) return selected
            if (progressiveFallback == null) {
                progressiveFallback = streams.firstOrNull { !it.audioOnly }
            }
        }
        return progressiveFallback
    }

    internal fun buildClientContext(regionCode: String): JSONObject {
        val utcOffsetMinutes = java.util.TimeZone.getDefault()
            .getOffset(System.currentTimeMillis()) / 60_000
        val profile = CLIENTS.first()
        return JSONObject()
            .put("clientName", profile.clientName)
            .put("clientVersion", profile.version)
            .put("hl", "en")
            .put("gl", DiscoverPlaybackOptions.normalizeRegion(regionCode))
            .put("utcOffsetMinutes", utcOffsetMinutes)
            .apply {
                profile.osName?.let { put("osName", it) }
                profile.osVersion?.let { put("osVersion", it) }
                profile.deviceMake?.let { put("deviceMake", it) }
                profile.deviceModel?.let { put("deviceModel", it) }
                profile.androidSdkVersion?.let { put("androidSdkVersion", it) }
            }
    }

    private fun requestPlayer(
        videoId: String,
        profile: PlayerClient,
        regionCode: String
    ): JSONObject {
        val utcOffsetMinutes = java.util.TimeZone.getDefault()
            .getOffset(System.currentTimeMillis()) / 60_000
        val clientContext = JSONObject()
            .put("clientName", profile.clientName)
            .put("clientVersion", profile.version)
            .put("hl", "en")
            .put("gl", DiscoverPlaybackOptions.normalizeRegion(regionCode))
            .put("utcOffsetMinutes", utcOffsetMinutes)
            .apply {
                profile.osName?.let { put("osName", it) }
                profile.osVersion?.let { put("osVersion", it) }
                profile.deviceMake?.let { put("deviceMake", it) }
                profile.deviceModel?.let { put("deviceModel", it) }
                profile.androidSdkVersion?.let { put("androidSdkVersion", it) }
            }
        val context = JSONObject().put("client", clientContext).apply {
            profile.embedUrl?.let { put("thirdParty", JSONObject().put("embedUrl", it)) }
        }
        val body = JSONObject()
            .put("context", context)
            .put("videoId", videoId)
            .put("contentCheckOk", true)
            .put("racyCheckOk", true)
        val request = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/player?key=$PUBLIC_API_KEY&prettyPrint=false")
            .header("User-Agent", profile.userAgent)
            .header("X-YouTube-Client-Name", profile.headerId)
            .header("X-YouTube-Client-Version", profile.version)
            .apply {
                if (profile.embedUrl != null) {
                    header("Origin", "https://www.youtube.com")
                    header("Referer", profile.embedUrl)
                }
            }
            .post(body.toString().toRequestBody(JSON_MEDIA))
            .build()
        http.newCall(request).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            check(response.isSuccessful) { "Player HTTP ${response.code} (${profile.id})" }
            return JSONObject(raw)
        }
    }

    internal fun parseStreams(
        player: JSONObject,
        profile: PlayerClient = CLIENTS.first()
    ): List<YouTubePlayerStream> {
        val status = player.optJSONObject("playabilityStatus")?.optString("status").orEmpty()
        if (status.isNotBlank() && status != "OK") return emptyList()
        val streaming = player.optJSONObject("streamingData") ?: return emptyList()
        val audio = collect(streaming.optJSONArray("adaptiveFormats"), profile, audioOnly = true)
            .filter { it.mimeType.startsWith("audio/", ignoreCase = true) }
        val progressive = collect(streaming.optJSONArray("formats"), profile, audioOnly = false)
            .filter {
                it.mimeType.startsWith("video/mp4", ignoreCase = true) ||
                    it.mimeType.startsWith("video/webm", ignoreCase = true)
            }
        return audio.sortedWith(
            compareByDescending<YouTubePlayerStream> { isOpus(it) }
                .thenByDescending { it.bitrateBps }
        ) + progressive.sortedByDescending { it.bitrateBps }
    }

    private fun collect(formats: JSONArray?, profile: PlayerClient, audioOnly: Boolean): List<YouTubePlayerStream> {
        if (formats == null) return emptyList()
        return buildList {
            for (index in 0 until formats.length()) {
                val item = formats.optJSONObject(index) ?: continue
                if (item.optBoolean("isDrm", false) || item.optJSONArray("drmFamilies") != null) continue
                val url = item.optString("url").trim()
                if (!isGoogleVideoUrl(url)) continue
                val mime = item.optString("mimeType").substringBefore(';').trim()
                if (mime.isEmpty()) continue
                val codec = mime.substringAfter('/', "").substringBefore(',').trim()
                val bitrate = item.optLong("averageBitrate", 0L).takeIf { it > 0L }
                    ?: item.optLong("bitrate", 0L)
                add(
                    YouTubePlayerStream(
                        url = url,
                        mimeType = mime,
                        bitrateBps = bitrate,
                        userAgent = profile.userAgent,
                        codec = codec,
                        itag = item.optInt("itag", 0),
                        client = profile.id,
                        audioOnly = audioOnly
                    )
                )
            }
        }
    }

    private fun isGoogleVideoUrl(value: String): Boolean {
        if (!value.startsWith("https://", ignoreCase = true)) return false
        val host = runCatching { java.net.URI(value).host }.getOrNull()?.lowercase().orEmpty()
        return host == "googlevideo.com" || host.endsWith(".googlevideo.com")
    }

    private fun isOpus(stream: YouTubePlayerStream): Boolean =
        stream.itag in OPUS_ITAGS ||
            stream.mimeType.contains("opus", ignoreCase = true) ||
            stream.mimeType.contains("webm", ignoreCase = true)

    internal data class PlayerClient(
        val id: String,
        val clientName: String,
        val version: String,
        val headerId: String,
        val userAgent: String,
        val osName: String? = null,
        val osVersion: String? = null,
        val deviceMake: String? = null,
        val deviceModel: String? = null,
        val androidSdkVersion: Int? = null,
        val embedUrl: String? = null
    )

    private companion object {
        private const val PUBLIC_API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
        private val VIDEO_ID = Regex("[A-Za-z0-9_-]{11}")
        private val OPUS_ITAGS = setOf(774, 251, 250, 249)
        private const val WEB_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"

        internal val CLIENTS = listOf(
            PlayerClient(
                id = "ANDROID_VR",
                clientName = "ANDROID_VR",
                version = "1.71.26",
                headerId = "28",
                userAgent = "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
                osName = "Android",
                osVersion = "12L",
                deviceMake = "Oculus",
                deviceModel = "Quest 3",
                androidSdkVersion = 32
            ),
            PlayerClient(
                id = "IOS",
                clientName = "IOS",
                version = "20.49.4",
                headerId = "5",
                userAgent = "com.google.ios.youtube/20.49.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
                osName = "iPhone",
                osVersion = "18.3.2.22D82",
                deviceMake = "Apple",
                deviceModel = "iPhone16,2"
            ),
            PlayerClient(
                id = "WEB_EMBEDDED",
                clientName = "WEB_EMBEDDED_PLAYER",
                version = "1.20250317.01.00",
                headerId = "56",
                userAgent = WEB_UA,
                embedUrl = "https://www.youtube.com/"
            )
        )
    }
}
