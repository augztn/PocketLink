package io.github.augztn.pocketlink.ssdbridge

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * YouTube Music catalogue client. InnerTube is used for catalogue data only;
 * NewPipeExtractor remains responsible for resolving playable media URLs.
 *
 * InnerTube is an undocumented upstream interface. Keep parsing defensive and
 * allow callers to fall back to NewPipe when the response shape changes.
 */
internal class YouTubeMusicCatalog(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .callTimeout(18, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()
) {
    @Volatile private var visitorData: String = ""

    fun search(query: String, limit: Int, regionCode: String = "IN"): List<Map<String, Any>> {
        val clean = query.trim()
        if (clean.length < 2) return emptyList()
        val filtered = runCatching {
            val response = post(
                "search",
                JSONObject().put("query", clean).put("params", SONGS_FILTER),
                regionCode
            )
            parseTracks(response, limit)
        }.getOrDefault(emptyList())
        if (filtered.isNotEmpty()) return filtered
        return runCatching {
            parseTracks(post("search", JSONObject().put("query", clean), regionCode), limit)
        }.getOrDefault(emptyList())
    }

    fun home(limit: Int, regionCode: String = "IN"): List<Map<String, Any>> {
        val charts = runCatching {
            parseTracks(post("browse", JSONObject().put("browseId", "FEmusic_charts"), regionCode), limit)
        }.getOrDefault(emptyList())
        if (charts.isNotEmpty()) return charts
        return runCatching {
            parseTracks(post("browse", JSONObject().put("browseId", "FEmusic_home"), regionCode), limit)
        }.getOrDefault(emptyList())
    }

    fun radio(videoId: String, limit: Int, regionCode: String = "IN"): List<Map<String, Any>> {
        require(VIDEO_ID.matches(videoId)) { "Invalid YouTube video ID." }
        val response = post(
            "next",
            JSONObject()
                .put("videoId", videoId)
                .put("playlistId", "RDAMVM$videoId")
                .put("isAudioOnly", true),
            regionCode
        )
        return parseTracks(response, limit).filterNot { it["videoId"] == videoId }
    }

    fun suggestions(input: String): List<String> {
        val clean = input.trim()
        if (clean.length < 2) return emptyList()
        val response = post("music/get_search_suggestions", JSONObject().put("input", clean), "IN")
        val values = mutableListOf<String>()
        collectStrings(response, values)
        return values.asSequence().map(String::trim).filter { it.length in 2..100 }
            .distinct().take(8).toList()
    }

    internal fun buildClientContext(regionCode: String): JSONObject {
        val utcOffsetMinutes = java.util.TimeZone.getDefault()
            .getOffset(System.currentTimeMillis()) / 60_000
        return JSONObject()
            .put("clientName", "WEB_REMIX")
            .put("clientVersion", WEB_REMIX_VERSION)
            .put("hl", "en")
            .put("gl", DiscoverPlaybackOptions.normalizeRegion(regionCode))
            .put("utcOffsetMinutes", utcOffsetMinutes)
    }

    private fun post(endpoint: String, payload: JSONObject, regionCode: String): JSONObject {
        val context = JSONObject().put("client", buildClientContext(regionCode))
        val body = JSONObject().put("context", context)
        val iterator = payload.keys()
        while (iterator.hasNext()) {
            val key = iterator.next()
            body.put(key, payload.get(key))
        }
        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/$endpoint?key=$PUBLIC_API_KEY&prettyPrint=false")
            .header("User-Agent", USER_AGENT)
            .header("Origin", "https://music.youtube.com")
            .header("Referer", "https://music.youtube.com/")
            .header("Content-Type", "application/json")
            .apply { if (visitorData.isNotBlank()) header("X-Goog-Visitor-Id", visitorData) }
            .post(body.toString().toRequestBody(JSON_MEDIA))
            .build()
        client.newCall(request).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw IOException("YouTube Music $endpoint returned HTTP ${response.code}")
            val json = JSONObject(raw)
            findVisitorData(json)?.let { visitorData = it }
            return json
        }
    }

    internal fun parseTracks(root: JSONObject, limit: Int): List<Map<String, Any>> {
        val renderers = mutableListOf<JSONObject>()
        collectRenderers(root, renderers)
        val unique = LinkedHashMap<String, Map<String, Any>>()
        for (renderer in renderers) {
            val watchEndpoint = renderer.optJSONObject("navigationEndpoint")?.optJSONObject("watchEndpoint")
            val videoId = renderer.optJSONObject("playlistItemData")?.optString("videoId")
                ?.takeIf { VIDEO_ID.matches(it) }
                ?: watchEndpoint?.optString("videoId")?.takeIf { VIDEO_ID.matches(it) }
                ?: renderer.optString("videoId").takeIf { VIDEO_ID.matches(it) }
                ?: continue
            val columns = renderer.optJSONArray("flexColumns")
            val title = if (columns != null && columns.length() > 0) {
                columnText(columns.optJSONObject(0))
            } else ""
            val resolvedTitle = title.ifBlank {
                renderer.optJSONObject("title")?.let(::textValue).orEmpty()
            }
            if (resolvedTitle.isBlank()) continue
            val artist = if (columns != null && columns.length() > 1) {
                columnText(columns.optJSONObject(1))
            } else {
                renderer.optJSONObject("subtitle")?.let(::textValue).orEmpty()
            }
            val duration = if (columns != null && columns.length() > 2) columnText(columns.optJSONObject(2)) else ""
            val thumbnail = findThumbnail(renderer)
                ?: "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
            unique.putIfAbsent(videoId, mapOf(
                "videoId" to videoId,
                "title" to resolvedTitle,
                "artist" to artist.ifBlank { "YouTube Music" },
                "durationText" to duration,
                "thumbnailUrl" to thumbnail
            ))
            if (unique.size >= limit.coerceIn(1, 50)) break
        }
        return unique.values.toList()
    }

    private fun collectRenderers(value: Any?, output: MutableList<JSONObject>) {
        when (value) {
            is JSONObject -> {
                val renderer = value.optJSONObject("musicResponsiveListItemRenderer")
                    ?: value.optJSONObject("musicTwoRowItemRenderer")
                if (renderer != null) output.add(renderer)
                val keys = value.keys()
                while (keys.hasNext()) collectRenderers(value.opt(keys.next()), output)
            }
            is JSONArray -> for (index in 0 until value.length()) collectRenderers(value.opt(index), output)
        }
    }

    private fun columnText(column: JSONObject?): String {
        if (column == null) return ""
        val renderer = column.optJSONObject("musicResponsiveListItemFlexColumnRenderer") ?: column
        return renderer.optJSONObject("text")?.let(::textValue).orEmpty()
    }

    private fun textValue(value: JSONObject): String {
        value.optString("simpleText").takeIf { it.isNotBlank() }?.let { return it }
        val runs = value.optJSONArray("runs") ?: return ""
        return (0 until runs.length()).mapNotNull { runs.optJSONObject(it)?.optString("text") }
            .joinToString("").trim()
    }

    private fun findThumbnail(root: JSONObject): String? {
        val thumbnails = mutableListOf<String>()
        collectThumbnailUrls(root, thumbnails)
        return thumbnails.lastOrNull()
    }

    private fun collectThumbnailUrls(value: Any?, output: MutableList<String>) {
        when (value) {
            is JSONObject -> {
                val thumbs = value.optJSONArray("thumbnails")
                if (thumbs != null) {
                    for (i in 0 until thumbs.length()) {
                        val url = thumbs.optJSONObject(i)?.optString("url").orEmpty()
                        if (url.startsWith("https://")) output.add(url)
                    }
                }
                val keys = value.keys()
                while (keys.hasNext()) collectThumbnailUrls(value.opt(keys.next()), output)
            }
            is JSONArray -> for (i in 0 until value.length()) collectThumbnailUrls(value.opt(i), output)
        }
    }

    private fun findVisitorData(value: Any?): String? {
        when (value) {
            is JSONObject -> {
                val direct = value.optString("visitorData").takeIf { it.isNotBlank() }
                if (direct != null) return direct
                val keys = value.keys()
                while (keys.hasNext()) findVisitorData(value.opt(keys.next()))?.let { return it }
            }
            is JSONArray -> for (i in 0 until value.length()) findVisitorData(value.opt(i))?.let { return it }
        }
        return null
    }

    private fun collectStrings(value: Any?, output: MutableList<String>) {
        when (value) {
            is JSONObject -> {
                val runs = value.optJSONArray("runs")
                if (runs != null) {
                    val text = (0 until runs.length()).mapNotNull {
                        runs.optJSONObject(it)?.optString("text")
                    }.joinToString("").trim()
                    if (text.isNotBlank()) output.add(text)
                }
                val keys = value.keys()
                while (keys.hasNext()) collectStrings(value.opt(keys.next()), output)
            }
            is JSONArray -> for (i in 0 until value.length()) collectStrings(value.opt(i), output)
        }
    }

    companion object {
        private const val PUBLIC_API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        private const val WEB_REMIX_VERSION = "1.20250317.01.00"
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
        private val VIDEO_ID = Regex("[A-Za-z0-9_-]{11}")
        private const val SONGS_FILTER = "EgWKAQIIAWoSEAMQBBAJEAoQBRAREAUYHRAF"
    }
}
