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
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Android-side YouTube audio discovery bridge.
 *
 * NewPipeExtractor performs player JavaScript signature and n-parameter
 * deciphering natively. Independent HTTP work runs in bounded lanes. Calls
 * into NewPipe remain serialized because its localization is process-global.
 */
internal object DiscoverBridge {
    private val discoverExecutor = boundedExecutor("PocketLink-Discover", workers = 2)
    private val metadataExecutor = boundedExecutor("PocketLink-Metadata", workers = 2)
    private val resolverExecutor = boundedExecutor("PocketLink-Resolver", workers = 1)
    private val newPipeLock = ReentrantLock()
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


    fun moodAndGenres(regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(discoverExecutor, result, "DISCOVER_MOODS_FAILED", "Could not load moods and genres.") {
            try {
                val sections = catalog.moodAndGenres(regionCode)
                mainHandler.post { result.success(sections) }
            } catch (error: Exception) {
                mainHandler.post { result.error("DISCOVER_MOODS_FAILED", error.message ?: "Could not load moods and genres.", null) }
            }
        }
    }

    fun browseMood(
        browseId: String,
        params: String?,
        limit: Int,
        regionCode: String,
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        submit(discoverExecutor, result, "DISCOVER_MOOD_BROWSE_FAILED", "Could not open this mood.") {
            try {
                val tracks = catalog.browseMood(browseId, params, limit.coerceIn(1, 50), regionCode)
                mainHandler.post { result.success(tracks) }
            } catch (error: Exception) {
                mainHandler.post { result.error("DISCOVER_MOOD_BROWSE_FAILED", error.message ?: "Could not open this mood.", null) }
            }
        }
    }

    fun search(query: String, limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(discoverExecutor, result, "DISCOVER_SEARCH_FAILED", "YouTube Music search failed.") {
            try {
                val cleanQuery = query.trim()
                require(cleanQuery.length >= 2) { "Enter at least two characters." }
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.search(cleanQuery, boundedLimit, regionCode)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    newPipeLock.withLock {
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

    fun homeFeed(limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(discoverExecutor, result, "DISCOVER_HOME_FAILED", "YouTube Music home is unavailable.") {
            try {
                val boundedLimit = limit.coerceIn(1, 50)
                val feed = catalog.homeFeed(boundedLimit, regionCode)
                val shelves = (feed["shelves"] as? List<*>)?.filterIsInstance<Map<String, Any>>().orEmpty()
                val response = if (shelves.isNotEmpty()) {
                    feed
                } else {
                    val fallback = newPipeLock.withLock {
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
                    mapOf(
                        "shelves" to if (fallback.isEmpty()) emptyList<Map<String, Any>>()
                            else listOf(mapOf("title" to "Trending in $regionCode", "tracks" to fallback)),
                        "continuation" to ""
                    )
                }
                mainHandler.post { result.success(response) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DISCOVER_HOME_FAILED", error.message ?: "YouTube Music home is unavailable.", null)
                }
            }
        }
    }

    fun moreHome(token: String, limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(discoverExecutor, result, "DISCOVER_HOME_MORE_FAILED", "Could not load more recommendations.") {
            try {
                val feed = catalog.moreHome(token, limit.coerceIn(1, 50))
                mainHandler.post { result.success(feed) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DISCOVER_HOME_MORE_FAILED", error.message ?: "Could not load more recommendations.", null)
                }
            }
        }
    }

    fun home(limit: Int, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(discoverExecutor, result, "DISCOVER_HOME_FAILED", "YouTube Music home is unavailable.") {
            try {
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.home(boundedLimit, regionCode)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    newPipeLock.withLock {
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
        submit(discoverExecutor, result, "DISCOVER_RADIO_FAILED", "Could not load radio recommendations.") {
            try {
                val id = videoId.trim()
                val boundedLimit = limit.coerceIn(1, 50)
                val catalogueTracks = catalog.radio(id, boundedLimit, regionCode)
                val tracks = if (catalogueTracks.isNotEmpty()) {
                    catalogueTracks
                } else {
                    newPipeLock.withLock {
                        ensureInitialized(regionCode)
                        StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$id")
                            .relatedItems.orEmpty()
                            .filterIsInstance<StreamInfoItem>()
                            .mapNotNull { it.toDiscoverTrack() }
                            .filter { it["videoId"] != id }
                            .distinctBy { it["videoId"] }
                            .take(boundedLimit)
                    }
                }
                mainHandler.post { result.success(tracks) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("DISCOVER_RADIO_FAILED", error.message ?: "Could not load radio recommendations.", null)
                }
            }
        }
    }

    fun lyrics(videoId: String, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(metadataExecutor, result, "DISCOVER_LYRICS_FAILED", "YouTube Music lyrics are unavailable.") {
            try {
                val payload = catalog.lyrics(videoId.trim(), regionCode)
                mainHandler.post { result.success(payload) }
            } catch (error: Exception) {
                mainHandler.post { result.error("DISCOVER_LYRICS_FAILED", error.message ?: "YouTube Music lyrics are unavailable.", null) }
            }
        }
    }

    fun captions(videoId: String, regionCode: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        submit(metadataExecutor, result, "DISCOVER_CAPTIONS_FAILED", "YouTube captions are unavailable.") {
            try {
                val payload = catalog.captions(videoId.trim(), regionCode)
                mainHandler.post { result.success(payload) }
            } catch (error: Exception) {
                mainHandler.post { result.error("DISCOVER_CAPTIONS_FAILED", error.message ?: "YouTube captions are unavailable.", null) }
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
        submit(resolverExecutor, result, "DISCOVER_STREAM_FAILED", "Could not resolve the YouTube audio stream.") {
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
        return newPipeLock.withLock {
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
            audioPayload to progressivePayload
        }
    }

    private fun boundedExecutor(name: String, workers: Int): ExecutorService {
        val sequence = AtomicInteger()
        val factory = ThreadFactory { task ->
            Thread(task, "$name-${sequence.incrementAndGet()}").apply { isDaemon = true }
        }
        return ThreadPoolExecutor(
            workers,
            workers,
            0L,
            TimeUnit.MILLISECONDS,
            ArrayBlockingQueue(32),
            factory,
            ThreadPoolExecutor.AbortPolicy()
        )
    }

    private fun submit(
        executor: ExecutorService,
        result: io.flutter.plugin.common.MethodChannel.Result,
        errorCode: String,
        fallbackMessage: String,
        task: () -> Unit
    ) {
        try {
            executor.execute(task)
        } catch (error: RejectedExecutionException) {
            mainHandler.post {
                result.error(errorCode, "Discover is busy. Please retry shortly.", null)
            }
        } catch (error: Exception) {
            mainHandler.post {
                result.error(errorCode, error.message ?: fallbackMessage, null)
            }
        }
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
