package io.github.augztn.pocketlink.ssdbridge

import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.io.IOException
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Android-side YouTube audio discovery bridge.
 *
 * NewPipeExtractor performs player JavaScript signature and n-parameter
 * deciphering natively. Network work is serialized off the platform thread.
 */
internal object DiscoverBridge {
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "PocketLink-Discover").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private val catalog = YouTubeMusicCatalog(httpClient)
    private val playerFallback = YouTubePlayerFallback(httpClient)
    @Volatile private var initialized = false
    private val initLock = Any()

    fun search(query: String, limit: Int, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                val cleanQuery = query.trim()
                require(cleanQuery.length >= 2) { "Enter at least two characters." }
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.search(cleanQuery, boundedLimit)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    ensureInitialized()
                    val handler = ServiceList.YouTube.searchQHFactory.fromQuery(
                        cleanQuery,
                        listOf("music_songs"),
                        ""
                    )
                    val info = SearchInfo.getInfo(ServiceList.YouTube, handler)
                    info.relatedItems.orEmpty()
                        .filterIsInstance<StreamInfoItem>()
                        .mapNotNull { item -> item.toDiscoverTrack() }
                        .distinctBy { it["videoId"] }
                        .take(boundedLimit)
                }
                mainHandler.post { result.success(tracks) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "DISCOVER_SEARCH_FAILED",
                        error.message ?: "YouTube Music search failed.",
                        null
                    )
                }
            }
        }
    }

    fun home(limit: Int, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.home(boundedLimit)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    ensureInitialized()
                    val handler = ServiceList.YouTube.searchQHFactory.fromQuery(
                        "top songs India",
                        listOf("music_songs"),
                        ""
                    )
                    SearchInfo.getInfo(ServiceList.YouTube, handler).relatedItems.orEmpty()
                        .filterIsInstance<StreamInfoItem>()
                        .mapNotNull { it.toDiscoverTrack() }
                        .distinctBy { it["videoId"] }
                        .take(boundedLimit)
                }
                mainHandler.post { result.success(tracks) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DISCOVER_HOME_FAILED", error.message ?: "YouTube Music home is unavailable.", null)
                }
            }
        }
    }

    fun radio(videoId: String, limit: Int, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                val id = videoId.trim()
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.radio(id, boundedLimit)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    ensureInitialized()
                    StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$id")
                        .relatedItems.orEmpty()
                        .filterIsInstance<StreamInfoItem>()
                        .mapNotNull { it.toDiscoverTrack() }
                        .filter { it["videoId"] != id }
                        .distinctBy { it["videoId"] }
                        .take(boundedLimit)
                }
                mainHandler.post { result.success(tracks) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DISCOVER_RADIO_FAILED", error.message ?: "Could not load radio recommendations.", null)
                }
            }
        }
    }

    fun resolve(videoId: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                ensureInitialized()
                val id = videoId.trim()
                require(ID_PATTERN.matches(id)) { "Invalid YouTube video ID." }

                var payload: Map<String, Any>? = null
                var newPipeFailure: String? = null
                val info = runCatching {
                    StreamInfo.getInfo(
                        ServiceList.YouTube,
                        "https://www.youtube.com/watch?v=$id"
                    )
                }.onFailure { error ->
                    // Keep diagnostics useful without logging signed URLs or request tokens.
                    newPipeFailure = error.javaClass.simpleName
                }.getOrNull()

                if (info != null) {
                    val audio = info.audioStreams.orEmpty()
                        .filter { stream -> stream.content.orEmpty().startsWith("https://") }
                        .sortedWith(
                            compareByDescending<AudioStream> { isOpus(it) }
                                .thenByDescending { it.averageBitrate }
                        )
                        .firstOrNull()
                    if (audio != null) {
                        payload = mapOf(
                            "url" to audio.content.orEmpty(),
                            "mimeType" to (audio.format?.mimeType ?: "audio/webm"),
                            "bitrateBps" to audio.averageBitrate.toLong() * 1000L,
                            "userAgent" to BROWSER_USER_AGENT,
                            "codec" to (audio.codec ?: ""),
                            "itag" to audio.itag,
                            "resolver" to "NewPipe"
                        )
                    } else {
                        // Some YouTube clients expose only muxed progressive streams.
                        val progressive = info.videoStreams.orEmpty()
                            .filter { !it.isVideoOnly && it.content.orEmpty().startsWith("https://") }
                            .maxByOrNull { it.height }
                        if (progressive != null) {
                            payload = mapOf(
                                "url" to progressive.content.orEmpty(),
                                "mimeType" to (progressive.format?.mimeType ?: "video/mp4"),
                                "bitrateBps" to 128_000L,
                                "userAgent" to BROWSER_USER_AGENT,
                                "codec" to (progressive.codec ?: ""),
                                "itag" to progressive.itag,
                                "resolver" to "NewPipe-progressive"
                            )
                        }
                    }
                }

                if (payload == null) {
                    val fallback = playerFallback.resolve(id)
                    if (fallback != null) {
                        payload = mapOf(
                            "url" to fallback.url,
                            "mimeType" to fallback.mimeType,
                            "bitrateBps" to fallback.bitrateBps,
                            "userAgent" to fallback.userAgent,
                            "codec" to fallback.codec,
                            "itag" to fallback.itag,
                            "resolver" to fallback.client
                        )
                    }
                }

                val resolved = payload
                    ?: throw IOException(
                        "No playable stream was exposed by NewPipe or the alternate YouTube player clients." +
                            (newPipeFailure?.let { " NewPipe: $it." } ?: "")
                    )
                mainHandler.post { result.success(resolved) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "DISCOVER_STREAM_FAILED",
                        error.message ?: "Could not resolve the YouTube audio stream.",
                        null
                    )
                }
            }
        }
    }

    private fun ensureInitialized() {
        if (initialized) return
        synchronized(initLock) {
            if (initialized) return
            NewPipe.init(
                object : Downloader() {
                    @Throws(IOException::class, ReCaptchaException::class)
                    override fun execute(request: Request): Response {
                        val method = request.httpMethod()
                        val data = request.dataToSend()
                        val body = when {
                            data != null -> data.toRequestBody(null, 0, data.size)
                            method.equals("POST", true) || method.equals("PUT", true) ->
                                ByteArray(0).toRequestBody(null, 0, 0)
                            else -> null
                        }
                        val builder = okhttp3.Request.Builder()
                            .url(request.url())
                            .method(method, body)
                            .header("User-Agent", BROWSER_USER_AGENT)
                            .header("Accept-Language", "en-US,en;q=0.9")
                        request.headers().forEach { (key, values) ->
                            builder.removeHeader(key)
                            values.forEach { value -> builder.addHeader(key, value) }
                        }
                        httpClient.newCall(builder.build()).execute().use { response ->
                            if (response.code == 429) {
                                throw ReCaptchaException("YouTube rate limited the request.", request.url())
                            }
                            return Response(
                                response.code,
                                response.message,
                                response.headers.toMultimap(),
                                response.body?.string().orEmpty(),
                                response.request.url.toString()
                            )
                        }
                    }
                },
                Localization("en", "IN"),
                ContentCountry("IN")
            )
            initialized = true
        }
    }

    private fun StreamInfoItem.toDiscoverTrack(): Map<String, Any> {
        val id = extractVideoId(url.orEmpty()) ?: return emptyMap()
        val title = name.orEmpty().trim()
        if (title.isEmpty()) return emptyMap()
        val durationSeconds = duration
        val durationText = if (durationSeconds > 0) {
            "${durationSeconds / 60}:${(durationSeconds % 60).toString().padStart(2, '0')}"
        } else ""
        val thumbnail = thumbnails.orEmpty().lastOrNull()?.url.orEmpty()
            .ifBlank { "https://i.ytimg.com/vi/$id/hqdefault.jpg" }
        return mapOf(
            "videoId" to id,
            "title" to title,
            "artist" to uploaderName.orEmpty().ifBlank { "Discover" },
            "durationText" to durationText,
            "thumbnailUrl" to thumbnail
        )
    }

    private fun extractVideoId(url: String): String? {
        val match = VIDEO_ID.find(url) ?: return null
        return match.groupValues.getOrNull(1)
    }

    private fun isOpus(stream: AudioStream): Boolean {
        val mime = stream.format?.mimeType.orEmpty()
        val codec = stream.codec.orEmpty()
        val suffix = stream.format?.suffix.orEmpty()
        return stream.itag in OPUS_ITAGS ||
            mime.contains("opus", true) ||
            mime.contains("webm", true) ||
            codec.contains("opus", true) ||
            suffix.equals("opus", true) ||
            suffix.equals("webm", true)
    }

    private const val BROWSER_USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"
    private val ID_PATTERN = Regex("[A-Za-z0-9_-]{6,20}")
    private val VIDEO_ID = Regex("(?:[?&]v=|youtu\\.be/)([A-Za-z0-9_-]{6,20})")
    private val OPUS_ITAGS = setOf(774, 251, 250, 249)
}
