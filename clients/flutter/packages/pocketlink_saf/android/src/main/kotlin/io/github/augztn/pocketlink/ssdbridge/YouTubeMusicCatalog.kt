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


    fun homeFeed(limit: Int, regionCode: String = "IN"): Map<String, Any> {
        val home = runCatching {
            post("browse", JSONObject().put("browseId", "FEmusic_home"), regionCode)
        }.getOrNull()
        var source = home
        var shelves = home?.let { parseHomeShelves(it, limit) }.orEmpty()
        if (shelves.isEmpty()) {
            source = post("browse", JSONObject().put("browseId", "FEmusic_charts"), regionCode)
            shelves = parseHomeShelves(source, limit)
        }
        if (shelves.isEmpty()) {
            val tracks = source?.let { parseTracks(it, limit) }.orEmpty()
            if (tracks.isNotEmpty()) {
                shelves = listOf(mapOf("title" to "Trending in $regionCode", "tracks" to tracks))
            }
        }
        return mapOf(
            "shelves" to shelves,
            "continuation" to (source?.let(::findContinuationToken) ?: "")
        )
    }

    fun moreHome(token: String, limit: Int, regionCode: String = "IN"): Map<String, Any> {
        require(token.isNotBlank() && token.length <= 8192) { "Invalid Home continuation token." }
        val response = post("browse", JSONObject().put("continuation", token), regionCode)
        return mapOf(
            "shelves" to parseHomeShelves(response, limit),
            "continuation" to (findContinuationToken(response) ?: "")
        )
    }

    internal fun parseHomeShelves(root: JSONObject, limit: Int): List<Map<String, Any>> {
        val renderers = mutableListOf<JSONObject>()
        collectHomeShelves(root, renderers)
        val seenVideoIds = mutableSetOf<String>()
        return renderers.mapNotNull { shelf ->
            val title = homeShelfTitle(shelf)
            if (title.isBlank()) return@mapNotNull null
            val tracks = parseTracks(shelf, limit).filter { track ->
                seenVideoIds.add(track["videoId"]?.toString().orEmpty())
            }
            if (tracks.isEmpty()) null else mapOf("title" to title, "tracks" to tracks)
        }
    }

    private fun collectHomeShelves(value: Any?, output: MutableList<JSONObject>) {
        when (value) {
            is JSONObject -> {
                val shelf = value.optJSONObject("musicCarouselShelfRenderer")
                    ?: value.optJSONObject("musicShelfRenderer")
                    ?: value.optJSONObject("musicImmersiveCarouselShelfRenderer")
                if (shelf != null) {
                    output.add(shelf)
                    return
                }
                val keys = value.keys()
                while (keys.hasNext()) collectHomeShelves(value.opt(keys.next()), output)
            }
            is JSONArray -> for (index in 0 until value.length()) {
                collectHomeShelves(value.opt(index), output)
            }
        }
    }

    private fun homeShelfTitle(shelf: JSONObject): String {
        val header = shelf.optJSONObject("header")
        val candidates = listOf(
            "musicCarouselShelfBasicHeaderRenderer",
            "musicShelfHeaderRenderer",
            "musicImmersiveCarouselShelfBasicHeaderRenderer"
        )
        for (key in candidates) {
            val title = header?.optJSONObject(key)?.optJSONObject("title")?.let(::textValue)
                .orEmpty().trim()
            if (title.isNotEmpty()) return title
        }
        return shelf.optJSONObject("title")?.let(::textValue).orEmpty().trim()
    }

    internal fun findContinuationToken(value: Any?): String? {
        when (value) {
            is JSONObject -> {
                value.optJSONObject("continuationCommand")?.optString("token")
                    ?.takeIf { it.isNotBlank() }?.let { return it }
                value.optJSONObject("nextContinuationData")?.optString("continuation")
                    ?.takeIf { it.isNotBlank() }?.let { return it }
                val keys = value.keys()
                while (keys.hasNext()) findContinuationToken(value.opt(keys.next()))?.let { return it }
            }
            is JSONArray -> for (index in 0 until value.length()) {
                findContinuationToken(value.opt(index))?.let { return it }
            }
        }
        return null
    }

    fun moodAndGenres(regionCode: String = "IN"): List<Map<String, Any>> {
        val response = post(
            "browse",
            JSONObject().put("browseId", "FEmusic_moods_and_genres"),
            regionCode
        )
        val sections = parseMoodAndGenres(response)
        if (sections.isEmpty()) {
            throw IOException(
                "YouTube Music returned no supported mood sections; its browse response structure may have changed."
            )
        }
        return sections
    }

    internal fun parseMoodAndGenres(root: JSONObject): List<Map<String, Any>> {
        val sections = mutableListOf<Map<String, Any>>()
        collectMoodSections(root, sections)
        return sections
    }

    fun browseMood(browseId: String, params: String?, limit: Int, regionCode: String): List<Map<String, Any>> {
        require(browseId.matches(Regex("[A-Za-z0-9_-]{3,128}"))) { "Invalid mood browse ID." }
        val payload = JSONObject().put("browseId", browseId)
        if (!params.isNullOrBlank()) payload.put("params", params)
        return parseTracks(post("browse", payload, regionCode), limit)
    }

    private fun collectMoodSections(value: Any?, output: MutableList<Map<String, Any>>) {
        when (value) {
            is JSONObject -> {
                val grid = value.optJSONObject("gridRenderer")
                if (grid != null) {
                    val title = grid.optJSONObject("header")
                        ?.optJSONObject("gridHeaderRenderer")
                        ?.optJSONObject("title")?.let(::textValue).orEmpty()
                    val items = mutableListOf<Map<String, Any>>()
                    val rows = grid.optJSONArray("items")
                    if (rows != null) for (index in 0 until rows.length()) {
                        val renderer = rows.optJSONObject(index)
                            ?.optJSONObject("musicNavigationButtonRenderer") ?: continue
                        val itemTitle = renderer.optJSONObject("buttonText")?.let(::textValue).orEmpty()
                        val endpoint = renderer.optJSONObject("clickCommand")
                            ?.optJSONObject("browseEndpoint") ?: continue
                        val browseId = endpoint.optString("browseId")
                        if (itemTitle.isBlank() || browseId.isBlank()) continue
                        val item = linkedMapOf<String, Any>(
                            "title" to itemTitle,
                            "browseId" to browseId,
                            "stripeColor" to (renderer.optJSONObject("solid")?.optLong("leftStripeColor") ?: 0L)
                        )
                        endpoint.optString("params").takeIf { it.isNotBlank() }?.let { item["params"] = it }
                        items.add(item)
                    }
                    if (title.isNotBlank() && items.isNotEmpty()) {
                        output.add(mapOf("title" to title, "items" to items))
                    }
                }
                val keys = value.keys()
                while (keys.hasNext()) collectMoodSections(value.opt(keys.next()), output)
            }
            is JSONArray -> for (index in 0 until value.length()) collectMoodSections(value.opt(index), output)
        }
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

    fun lyrics(videoId: String, regionCode: String): Map<String, Any>? {
        if (!VIDEO_ID.matches(videoId)) return null
        val next = post("next", JSONObject().put("videoId", videoId), regionCode)
        val browseId = findLyricsBrowseId(next)
        if (browseId != null) {
            val browse = post("browse", JSONObject().put("browseId", browseId), regionCode)
            val timed = mutableListOf<Map<String, Any>>()
            collectTimedLyrics(browse, timed)
            if (timed.isNotEmpty()) return mapOf("synced" to true, "lines" to timed)
        }
        val plain = runCatching {
            val response = post("music/get_lyrics", JSONObject().put("videoId", videoId), regionCode)
            findTextValue(response, "description")
        }.getOrNull()?.trim().orEmpty()
        if (plain.isNotEmpty()) return mapOf(
            "synced" to false,
            "lines" to plain.split(Regex("\\r?\\n")).filter { it.isNotBlank() }
                .map { mapOf("timeMs" to 0, "text" to it.trim()) }
        )
        return null
    }

    fun captions(videoId: String, regionCode: String): Map<String, Any>? {
        if (!VIDEO_ID.matches(videoId)) return null
        val id = videoId.toByteArray(Charsets.UTF_8)
        val bytes = byteArrayOf(10, id.size.toByte()) + id
        val params = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
        val response = post("get_transcript", JSONObject().put("params", params), regionCode)
        val lines = mutableListOf<Map<String, Any>>()
        collectCaptions(response, lines)
        return if (lines.isEmpty()) null else mapOf("synced" to true, "lines" to lines)
    }

    private fun findLyricsBrowseId(value: Any?): String? {
        when (value) {
            is JSONObject -> {
                val browse = value.optString("browseId")
                val pageType = value.optJSONObject("browseEndpointContextSupportedConfigs")
                    ?.optJSONObject("browseEndpointContextMusicConfig")?.optString("pageType")
                if (browse.isNotBlank() && pageType == "MUSIC_PAGE_TYPE_TRACK_LYRICS") return browse
                val keys = value.keys()
                while (keys.hasNext()) findLyricsBrowseId(value.opt(keys.next()))?.let { return it }
            }
            is JSONArray -> for (i in 0 until value.length()) findLyricsBrowseId(value.opt(i))?.let { return it }
        }
        return null
    }

    private fun collectTimedLyrics(value: Any?, output: MutableList<Map<String, Any>>) {
        when (value) {
            is JSONObject -> {
                val entries = value.optJSONArray("timedLyricsData")
                if (entries != null) for (i in 0 until entries.length()) {
                    val entry = entries.optJSONObject(i) ?: continue
                    val text = entry.optString("lyricLine").trim()
                    val cue = entry.optJSONObject("cueRange") ?: continue
                    val start = cue.optString("startTimeMilliseconds").toLongOrNull() ?: continue
                    if (text.isNotEmpty()) output.add(mapOf(
                        "timeMs" to start,
                        "text" to text,
                        "endTimeMs" to (cue.optString("endTimeMilliseconds").toLongOrNull() ?: start)
                    ))
                }
                val keys = value.keys()
                while (keys.hasNext()) collectTimedLyrics(value.opt(keys.next()), output)
            }
            is JSONArray -> for (i in 0 until value.length()) collectTimedLyrics(value.opt(i), output)
        }
    }

    private fun collectCaptions(value: Any?, output: MutableList<Map<String, Any>>) {
        when (value) {
            is JSONObject -> {
                val cue = value.optJSONObject("transcriptCueRenderer")
                if (cue != null) {
                    val start = cue.optString("startOffsetMs").toLongOrNull()
                    val text = cue.optJSONObject("cue")?.let(::textValue).orEmpty().trim()
                    if (start != null && text.isNotEmpty()) output.add(mapOf("timeMs" to start, "text" to text))
                }
                val keys = value.keys()
                while (keys.hasNext()) collectCaptions(value.opt(keys.next()), output)
            }
            is JSONArray -> for (i in 0 until value.length()) collectCaptions(value.opt(i), output)
        }
    }

    private fun findTextValue(value: Any?, wantedKey: String): String? {
        when (value) {
            is JSONObject -> {
                val direct = value.optJSONObject(wantedKey)
                if (direct != null) return textValue(direct)
                val keys = value.keys()
                while (keys.hasNext()) findTextValue(value.opt(keys.next()), wantedKey)?.let { return it }
            }
            is JSONArray -> for (i in 0 until value.length()) findTextValue(value.opt(i), wantedKey)?.let { return it }
        }
        return null
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

    internal fun buildRequest(endpoint: String, payload: JSONObject, regionCode: String): Request {
        val context = JSONObject().put("client", buildClientContext(regionCode))
        val body = JSONObject().put("context", context)
        val iterator = payload.keys()
        while (iterator.hasNext()) {
            val key = iterator.next()
            body.put(key, payload.get(key))
        }
        return Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/$endpoint?key=$PUBLIC_API_KEY&prettyPrint=false")
            .header("User-Agent", USER_AGENT)
            .header("Origin", "https://music.youtube.com")
            .header("Referer", "https://music.youtube.com/")
            .header("Content-Type", "application/json")
            .header("X-Goog-Api-Format-Version", "1")
            .header("X-YouTube-Client-Name", "67")
            .header("X-YouTube-Client-Version", WEB_REMIX_VERSION)
            .apply { if (visitorData.isNotBlank()) header("X-Goog-Visitor-Id", visitorData) }
            .post(body.toString().toRequestBody(JSON_MEDIA))
            .build()
    }

    private fun post(endpoint: String, payload: JSONObject, regionCode: String): JSONObject {
        val request = buildRequest(endpoint, payload, regionCode)
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

    private data class ThumbnailCandidate(
        val url: String,
        val width: Int,
        val height: Int,
        val order: Int
    ) {
        val area: Long get() = width.toLong() * height.toLong()
    }

    private fun findThumbnail(root: JSONObject): String? {
        val thumbnails = mutableListOf<ThumbnailCandidate>()
        collectThumbnailUrls(root, thumbnails)
        val selected = thumbnails.maxWithOrNull(
            compareBy<ThumbnailCandidate> { it.area }.thenBy { it.order }
        ) ?: return null
        return upgradeArtworkResolution(selected.url)
    }

    private fun upgradeArtworkResolution(url: String): String {
        // Preserve the image identifier and CDN parameters while requesting
        // a larger rendition from YouTube Music's image CDN.
        return if (url.contains("googleusercontent.com/") &&
            Regex("=w\\d+-h\\d+").containsMatchIn(url)
        ) {
            url.replace(Regex("=w\\d+-h\\d+"), "=w1200-h1200")
        } else {
            url
        }
    }

    private fun collectThumbnailUrls(value: Any?, output: MutableList<ThumbnailCandidate>) {
        when (value) {
            is JSONObject -> {
                val thumbs = value.optJSONArray("thumbnails")
                if (thumbs != null) {
                    for (i in 0 until thumbs.length()) {
                        val item = thumbs.optJSONObject(i) ?: continue
                        val url = item.optString("url")
                        if (url.startsWith("https://")) {
                            output.add(ThumbnailCandidate(
                                url = url,
                                width = item.optInt("width"),
                                height = item.optInt("height"),
                                order = output.size
                            ))
                        }
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
        private const val WEB_REMIX_VERSION = "1.20260707.12.00"
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
        private val VIDEO_ID = Regex("[A-Za-z0-9_-]{11}")
        private const val SONGS_FILTER = "EgWKAQIIAWoSEAMQBBAJEAoQBRAREAUYHRAF"
    }
}
