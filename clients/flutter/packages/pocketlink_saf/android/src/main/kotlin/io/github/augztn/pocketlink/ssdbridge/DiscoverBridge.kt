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
    @Volatile private var initializedCountry: String? = null
    @Volatile private var lastSuccessfulResolver: String? = null
    private val initLock = Any()

    fun search(query: String, limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                val cleanQuery = query.trim()
                require(cleanQuery.length >= 2) { "Enter at least two characters." }
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.search(cleanQuery, boundedLimit, regionCode)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    ensureInitialized(regionCode)
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

    fun home(limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.home(boundedLimit, regionCode)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    ensureInitialized(regionCode)
                    val handler = ServiceList.YouTube.searchQHFactory.fromQuery(
                        "top songs",
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

    fun radio(videoId: String, limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        executor.execute {
            try {
                val id = videoId.trim()
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.radio(id, boundedLimit, regionCode)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    ensureInitialized(regionCode)
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

    fun resolve(
        videoId: String,
        quality: String,
        resolverProfile: String,
        regionCode: String,
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        executor.execute {
            try {
                val id = videoId.trim()
                require(ID_PATTERN.matches(id)) { "Invalid YouTube video ID." }
                val selectedQuality = DiscoverPlaybackOptions.normalizeQuality(quality)
                val selectedRegion = DiscoverPlaybackOptions.normalizeRegion(regionCode)
                val order = DiscoverPlaybackOptions.resolverOrder(
                    resolverProfile,
                    lastSuccessfulResolver
                )
                var payload: Map<String, Any>? = null
                var progressiveFallback: Map<String, Any>? = null
                var newPipeFailure: String? = null
                var newPipeAttempted = false

                for (resolver in order) {
                    when (resolver) {
                        "PLAYER_API" -> {
                            val candidate = resolveWithPlayerApi(id, selectedRegion, selectedQuality)
                            if (candidate?.get("audioOnly") == false) {
                                if (progressiveFallback == null) progressiveFallback = candidate
                            } else if (candidate != null) {
                                payload = candidate
                                lastSuccessfulResolver = "PLAYER_API"
                            }
                        }
                        else -> {
                            newPipeAttempted = true
                            val streams = runCatching {
                                resolveNewPipeStreams(id, selectedRegion, selectedQuality)
                            }.onFailure { error ->
                                newPipeFailure = error.javaClass.simpleName
                            }.getOrNull()
                            if (progressiveFallback == null) progressiveFallback = streams?.second
                            if (streams?.first != null) {
                                payload = streams.first
                                lastSuccessfulResolver = "NEWPIPE"
                            }
                        }
                    }
                    if (payload != null) break
                }

                if (payload == null && !newPipeAttempted) {
                    val streams = runCatching {
                        resolveNewPipeStreams(id, selectedRegion, selectedQuality)
                    }.onFailure { error ->
                        newPipeFailure = error.javaClass.simpleName
                    }.getOrNull()
                    if (progressiveFallback == null) progressiveFallback = streams?.second
                    if (streams?.first != null) {
                        payload = streams.first
                        lastSuccessfulResolver = "NEWPIPE"
                    }
                }
                if (payload == null) payload = progressiveFallback

                val resolved = payload ?: throw IOException(
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

    private fun resolveWithPlayerApi(
        videoId: String,
        regionCode: String,
        quality: String
    ): Map<String, Any>? {
        val stream = playerFallback.resolve(videoId, regionCode, quality) ?: return null
        val reason = if (stream.audioOnly) {
            DiscoverPlaybackOptions.qualityFallbackReason(quality, stream.bitrateBps)
        } else {
            "Only a muxed progressive stream was available; the requested audio-only quality could not be applied."
        }
        return mapOf(
            "url" to stream.url,
            "mimeType" to stream.mimeType,
            "bitrateBps" to stream.bitrateBps,
            "userAgent" to stream.userAgent,
            "codec" to stream.codec,
            "itag" to stream.itag,
            "resolver" to stream.client,
            "quality" to quality,
            "qualityFallbackReason" to (reason ?: ""),
            "audioOnly" to stream.audioOnly
        )
    }

    private fun resolveNewPipeStreams(
        videoId: String,
        regionCode: String,
        quality: String
    ): Pair<Map<String, Any>?, Map<String, Any>?> {
        ensureInitialized(regionCode)
        val info = StreamInfo.getInfo(
            ServiceList.YouTube,
            "https://www.youtube.com/watch?v=$videoId"
        )
        val audio = info.audioStreams.orEmpty()
            .filter { it.content.orEmpty().startsWith("https://") }
        val selectedAudio = DiscoverPlaybackOptions.selectAudioFormat(
            audio,
            quality,
            { it.averageBitrate.toLong().coerceAtLeast(0L) * 1000L },
            { isOpus(it) }
        )
        val audioPayload = selectedAudio?.let {
            val bitrate = it.averageBitrate.toLong().coerceAtLeast(0L) * 1000L
            mapOf(
                "url" to it.content.orEmpty(),
                "mimeType" to (it.format?.mimeType ?: "audio/webm"),
                "bitrateBps" to bitrate,
                "userAgent" to BROWSER_USER_AGENT,
                "codec" to (it.codec ?: ""),
                "itag" to it.itag,
                "resolver" to "NewPipe",
                "quality" to quality,
                "qualityFallbackReason" to (DiscoverPlaybackOptions.qualityFallbackReason(quality, bitrate) ?: ""),
                "audioOnly" to true
            )
        }
        val progressivePayload = info.videoStreams.orEmpty()
            .filter { !it.isVideoOnly && it.content.orEmpty().startsWith("https://") }
            .maxByOrNull { it.height }
            ?.let {
                mapOf(
                    "url" to it.content.orEmpty(),
                    "mimeType" to (it.format?.mimeType ?: "video/mp4"),
                    "bitrateBps" to 0L,
                    "userAgent" to BROWSER_USER_AGENT,
                    "codec" to (it.codec ?: ""),
                    "itag" to it.itag,
                    "resolver" to "NewPipe-progressive",
                    "quality" to quality,
                    "qualityFallbackReason" to "Only a muxed progressive stream was available; the requested audio-only quality could not be applied.",
                    "audioOnly" to false
                )
            }
        return audioPayload to progressivePayload
    }

    private fun ensureInitialized(regionCode: String) {
        val country = DiscoverPlaybackOptions.normalizeRegion(regionCode)
        if (initializedCountry == country) return
        synchronized(initLock) {
            if (initializedCountry == country) return
            if (initializedCountry == null) {
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
                    Localization("en", country),
                    ContentCountry(country)
                )
            } else {
                NewPipe.setupLocalization(
                    Localization("en", country),
                    ContentCountry(country)
                )
            }
            initializedCountry = country
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
