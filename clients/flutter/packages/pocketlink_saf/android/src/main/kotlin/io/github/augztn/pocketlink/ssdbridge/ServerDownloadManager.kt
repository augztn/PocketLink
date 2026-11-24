package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max

/**
 * Persistent URL-to-host-storage queue. Jobs are stored in app-private preferences;
 * payload bytes are streamed directly to a staging file and atomically finalized.
 */
internal class ServerDownloadManager(
    context: Context,
    private val root: () -> File,
    private val markMediaIndexDirty: () -> Unit
) : AutoCloseable {
    private data class Job(
        val id: String,
        val url: String,
        var fileName: String,
        val requestedDirectory: String?,
        val requestedFileName: String?,
        var destinationPath: String?,
        val createdAt: Long,
        var downloadedBytes: Long = 0,
        var totalBytes: Long? = null,
        var speedBytesPerSecond: Long = 0,
        var status: String = QUEUED,
        var error: String? = null
    )

    private val preferences = context.getSharedPreferences("server-downloads", Context.MODE_PRIVATE)
    private val lock = Any()
    private val jobs = LinkedHashMap<String, Job>()
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PocketLink-server-downloads").apply { isDaemon = true }
    }
    private val client = OkHttpClient.Builder()
        .dns(ValidatingDns)
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .build()
    @Volatile private var activeCall: okhttp3.Call? = null
    @Volatile private var started = false
    @Volatile private var closed = false

    init {
        load()
    }

    fun start() {
        synchronized(lock) {
            if (closed || started) return
            started = true
            jobs.values.filter { it.status == DOWNLOADING }.forEach {
                it.status = QUEUED
                it.speedBytesPerSecond = 0
            }
            persistLocked()
        }
        pump()
    }

    fun enqueue(rawUrl: String, directory: String?, filenameOverride: String?): JSONObject {
        val url = validateUrl(rawUrl).toString()
        val normalizedDirectory = directory?.trim()?.trim('/')?.takeIf { it.isNotEmpty() }
        if (normalizedDirectory != null) resolveDirectory(normalizedDirectory)
        val normalizedFileName = filenameOverride?.trim()?.takeIf { it.isNotEmpty() }?.let(::sanitizeFilename)
        val job = Job(
            id = UUID.randomUUID().toString(),
            url = url,
            fileName = normalizedFileName ?: filenameFromUrl(url),
            requestedDirectory = normalizedDirectory,
            requestedFileName = normalizedFileName,
            destinationPath = null,
            createdAt = System.currentTimeMillis()
        )
        synchronized(lock) {
            check(!closed) { "Download service is unavailable" }
            jobs[job.id] = job
            persistLocked()
        }
        pump()
        return jobJson(job)
    }

    fun list(): JSONObject = synchronized(lock) {
        val values = JSONArray()
        jobs.values.sortedByDescending { it.createdAt }.forEach { values.put(jobJson(it)) }
        JSONObject().put("items", values)
    }

    fun pause(id: String): JSONObject? {
        var wasActive = false
        val job = synchronized(lock) {
            val value = jobs[id] ?: return null
            if (value.status == COMPLETED || value.status == CANCELLED) return jobJson(value)
            wasActive = value.status == DOWNLOADING
            value.status = PAUSED
            value.speedBytesPerSecond = 0
            persistLocked()
            jobJson(value)
        }
        if (wasActive) activeCall?.cancel()
        return job
    }

    fun resume(id: String): JSONObject? {
        val result = synchronized(lock) {
            val job = jobs[id] ?: return null
            if (job.status == COMPLETED) return jobJson(job)
            job.status = QUEUED
            job.error = null
            job.speedBytesPerSecond = 0
            persistLocked()
            jobJson(job)
        }
        pump()
        return result
    }

    fun cancel(id: String): JSONObject? {
        var wasActive = false
        val result = synchronized(lock) {
            val job = jobs[id] ?: return null
            wasActive = job.status == DOWNLOADING
            if (job.status != COMPLETED) job.status = CANCELLED
            job.speedBytesPerSecond = 0
            persistLocked()
            jobJson(job)
        }
        if (wasActive) activeCall?.cancel()
        return result
    }

    fun remove(id: String, deleteFile: Boolean): Boolean {
        var wasActive = false
        val job = synchronized(lock) {
            val value = jobs.remove(id) ?: return false
            wasActive = value.status == DOWNLOADING
            persistLocked()
            value
        }
        if (wasActive) activeCall?.cancel()
        job.destinationPath?.let { path ->
            runCatching { File("$path.part").delete() }
            if (deleteFile) runCatching { File(path).delete() }
        }
        return true
    }

    private fun pump() {
        val next = synchronized(lock) {
            if (!started || closed || jobs.values.any { it.status == DOWNLOADING }) return
            jobs.values.firstOrNull { it.status == QUEUED }?.also {
                it.status = DOWNLOADING
                it.error = null
                persistLocked()
            }
        } ?: return
        executor.execute { runJob(next) }
    }

    private fun runJob(job: Job) {
        var response: okhttp3.Response? = null
        try {
            val existingTarget = job.destinationPath?.let(::File)
            if (existingTarget?.isFile == true &&
                ((job.totalBytes != null && existingTarget.length() == job.totalBytes) ||
                    (job.downloadedBytes > 0 && existingTarget.length() >= job.downloadedBytes))) {
                synchronized(lock) {
                    job.status = COMPLETED
                    job.downloadedBytes = existingTarget.length()
                    job.speedBytesPerSecond = 0
                    job.error = null
                    persistLocked()
                }
                markMediaIndexDirty()
                return
            }
            var currentUrl = job.url
            var redirects = 0
            var call: okhttp3.Call
            while (true) {
                val uri = validateUrl(currentUrl)
                val requestBuilder = Request.Builder().url(uri.toString()).get()
                val currentPart = job.destinationPath?.let { File("$it.part") }
                val offset = currentPart?.takeIf { it.isFile }?.length() ?: 0L
                if (offset > 0) requestBuilder.header("Range", "bytes=$offset-")
                call = client.newCall(requestBuilder.build())
                activeCall = call
                response = call.execute()
                if (response!!.code in 300..399) {
                    val location = response!!.header("Location")
                        ?: throw IOException("Download redirect did not include a destination")
                    if (++redirects > MAX_REDIRECTS) throw IOException("Too many download redirects")
                    currentUrl = uri.resolve(location)?.toString()
                        ?: throw IOException("Invalid download redirect")
                    validateUrl(currentUrl)
                    response!!.close()
                    response = null
                    continue
                }
                break
            }

            val result = response!!
            if (!result.isSuccessful) throw IOException("Download server returned HTTP ${result.code}")
            val body = result.body ?: throw IOException("Download response was empty")
            val name = job.requestedFileName
                ?: filenameFromHeaders(result.header("Content-Disposition"), currentUrl)
            if (job.destinationPath == null) {
                val directory = destinationDirectory(job.requestedDirectory, name, result.header("Content-Type"))
                val target = uniqueFile(directory, name)
                synchronized(lock) {
                    if (job.destinationPath == null) {
                        job.fileName = name
                        job.destinationPath = target.canonicalPath
                        persistLocked()
                    }
                }
            }
            val target = File(job.destinationPath!!)
            val part = File("${target.path}.part")
            target.parentFile?.let { if (!it.exists() && !it.mkdirs()) throw IOException("Cannot create download folder") }
            val offset = if (part.exists()) part.length() else 0L
            val partialResponse = result.code == 206
            val rangeStart = result.header("Content-Range")
                ?.substringAfter("bytes ")
                ?.substringBefore('-')
                ?.toLongOrNull()
            if (offset > 0 && partialResponse && rangeStart != offset) {
                part.delete()
                throw IOException("Download server returned an invalid resume range")
            }
            val append = offset > 0 && partialResponse
            if (offset > 0 && !partialResponse && !part.delete()) {
                throw IOException("Cannot restart partial download")
            }
            val contentRangeTotal = result.header("Content-Range")?.substringAfterLast('/')?.toLongOrNull()
            synchronized(lock) {
                job.totalBytes = contentRangeTotal ?: body.contentLength().takeIf { it >= 0 }?.let { it + if (append) offset else 0L }
                job.downloadedBytes = if (append) offset else 0L
                persistLocked()
            }
            val startedAt = System.nanoTime()
            var sampleAt = startedAt
            var sampleBytes = job.downloadedBytes
            var lastPersistAt = startedAt
            body.byteStream().use { input ->
                FileOutputStream(part, append).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        synchronized(lock) {
                            if (job.status != DOWNLOADING || closed) throw InterruptedDownload()
                        }
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        val now = System.nanoTime()
                        synchronized(lock) {
                            job.downloadedBytes += count
                            if (now - sampleAt >= 500_000_000L) {
                                job.speedBytesPerSecond = ((job.downloadedBytes - sampleBytes) * 1_000_000_000L /
                                    max(1L, now - sampleAt))
                                sampleAt = now
                                sampleBytes = job.downloadedBytes
                            }
                            if (now - lastPersistAt >= 1_000_000_000L) {
                                persistLocked()
                                lastPersistAt = now
                            }
                        }
                    }
                    output.fd.sync()
                }
            }
            synchronized(lock) {
                if (job.status != DOWNLOADING || closed) throw InterruptedDownload()
                persistLocked()
            }
            if (target.exists()) throw IOException("A file with this name already exists")
            if (!part.renameTo(target)) throw IOException("Could not finalize downloaded file")
            synchronized(lock) {
                job.status = COMPLETED
                job.downloadedBytes = target.length()
                job.totalBytes = target.length()
                job.speedBytesPerSecond = 0
                job.error = null
                persistLocked()
            }
            markMediaIndexDirty()
        } catch (_: InterruptedDownload) {
            // Pause/cancel/host shutdown already persisted the intended state.
        } catch (error: Exception) {
            synchronized(lock) {
                if (job.status == DOWNLOADING) {
                    job.status = FAILED
                    job.error = error.message?.take(300) ?: "Download failed"
                    job.speedBytesPerSecond = 0
                    persistLocked()
                }
            }
        } finally {
            response?.close()
            activeCall = null
            pump()
        }
    }

    private fun destinationDirectory(requested: String?, name: String, mime: String?): File {
        val relative = requested ?: "Downloads/PocketLink"
        val base = resolveDirectory(relative)
        if (requested != null) return base
        val category = categoryFor(name, mime)
        val folder = File(base, category)
        if (!folder.exists() && !folder.mkdirs()) throw IOException("Cannot create $category folder")
        return folder
    }

    private fun resolveDirectory(relative: String): File {
        if (relative.startsWith("/") || relative.split('/').any { it.isBlank() || it == "." || it == ".." } ||
            relative.any { it.code < 32 } || relative.contains('\\')) {
            throw IllegalArgumentException("Invalid destination folder")
        }
        val base = root().canonicalFile
        val target = File(base, relative).canonicalFile
        if (target != base && !target.path.startsWith(base.path + File.separator)) {
            throw IllegalArgumentException("Destination is outside shared storage")
        }
        if (target.exists() && !target.isDirectory) throw IllegalArgumentException("Destination is not a folder")
        if (!target.exists() && !target.mkdirs()) throw IOException("Cannot create destination folder")
        return target
    }

    private fun uniqueFile(directory: File, name: String): File {
        val extension = name.substringAfterLast('.', "").takeIf { it.isNotEmpty() }?.let { ".$it" } ?: ""
        val stem = if (extension.isEmpty()) name else name.dropLast(extension.length)
        var candidate = File(directory, name)
        var index = 1
        while (candidate.exists() || File("${candidate.path}.part").exists()) {
            candidate = File(directory, "$stem ($index)$extension")
            index++
        }
        return candidate
    }

    private fun load() = synchronized(lock) {
        val array = runCatching { JSONArray(preferences.getString(KEY_JOBS, "[]")) }.getOrNull() ?: JSONArray()
        for (index in 0 until array.length()) {
            val value = array.optJSONObject(index) ?: continue
            val job = runCatching {
                Job(
                    id = value.getString("id"),
                    url = value.getString("url"),
                    fileName = value.optString("file_name", "download"),
                    requestedDirectory = value.optString("requested_directory").takeIf { it.isNotBlank() },
                    requestedFileName = value.optString("requested_file_name").takeIf { it.isNotBlank() },
                    destinationPath = value.optString("destination_path").takeIf { it.isNotBlank() },
                    createdAt = value.optLong("created_at"),
                    downloadedBytes = value.optLong("downloaded_bytes"),
                    totalBytes = if (value.isNull("total_bytes")) null else value.optLong("total_bytes"),
                    status = value.optString("status", PAUSED),
                    error = value.optString("error").takeIf { it.isNotBlank() }
                )
            }.getOrNull() ?: continue
            jobs[job.id] = job
        }
    }

    private fun persistLocked() {
        val array = JSONArray()
        jobs.values.forEach { job ->
            array.put(JSONObject()
                .put("id", job.id)
                .put("url", job.url)
                .put("file_name", job.fileName)
                .put("requested_directory", job.requestedDirectory)
                .put("requested_file_name", job.requestedFileName)
                .put("destination_path", job.destinationPath)
                .put("created_at", job.createdAt)
                .put("downloaded_bytes", job.downloadedBytes)
                .put("total_bytes", job.totalBytes ?: JSONObject.NULL)
                .put("speed_bytes_per_second", job.speedBytesPerSecond)
                .put("status", job.status)
                .put("error", job.error))
        }
        preferences.edit().putString(KEY_JOBS, array.toString()).commit()
    }

    private fun jobJson(job: Job) = JSONObject()
        .put("id", job.id)
        .put("url", job.url)
        .put("file_name", job.fileName)
        .put("destination_path", job.destinationPath ?: JSONObject.NULL)
        .put("created_at", job.createdAt)
        .put("downloaded_bytes", job.downloadedBytes)
        .put("total_bytes", job.totalBytes ?: JSONObject.NULL)
        .put("speed_bytes_per_second", job.speedBytesPerSecond)
        .put("status", job.status)
        .put("error", job.error ?: JSONObject.NULL)

    override fun close() {
        synchronized(lock) {
            if (closed) return
            closed = true
            jobs.values.filter { it.status == DOWNLOADING }.forEach {
                it.status = QUEUED
                it.speedBytesPerSecond = 0
            }
            persistLocked()
        }
        activeCall?.cancel()
        executor.shutdownNow()
        client.dispatcher.cancelAll()
        client.connectionPool.evictAll()
    }

    private class InterruptedDownload : IOException()

    companion object {
        private const val KEY_JOBS = "jobs_v1"
        private const val MAX_REDIRECTS = 5
        private const val QUEUED = "queued"
        private const val DOWNLOADING = "downloading"
        private const val PAUSED = "paused"
        private const val COMPLETED = "completed"
        private const val FAILED = "failed"
        private const val CANCELLED = "cancelled"

        private val ValidatingDns = Dns { hostname ->
            val addresses = Dns.SYSTEM.lookup(hostname)
            if (addresses.isEmpty() || addresses.any(::isUnsafeAddress)) {
                throw IOException("Downloads to private or local network addresses are blocked")
            }
            addresses
        }

        private fun isUnsafeAddress(address: InetAddress): Boolean {
            val host = address.hostAddress.lowercase(Locale.ROOT)
            return address.isAnyLocalAddress || address.isLoopbackAddress ||
                address.isLinkLocalAddress || address.isSiteLocalAddress ||
                address.isMulticastAddress || host.startsWith("fc") || host.startsWith("fd") ||
                (address.address.size == 4 &&
                    (address.address[0].toInt() and 0xff) == 100 &&
                    (address.address[1].toInt() and 0xff) in 64..127)
        }

        private fun validateUrl(value: String): URI {
            val uri = try { URI(value.trim()) } catch (_: Exception) {
                throw IllegalArgumentException("Enter a valid HTTP or HTTPS URL")
            }
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            if ((scheme != "http" && scheme != "https") ||
                uri.host.isNullOrBlank() || uri.rawUserInfo != null) {
                throw IllegalArgumentException("Enter a valid HTTP or HTTPS URL without credentials")
            }
            val host = uri.host
            val literal = runCatching { InetAddress.getByName(host) }.getOrNull()
            if (literal != null && isUnsafeAddress(literal)) {
                throw IllegalArgumentException("Downloads to private or local network addresses are blocked")
            }
            return uri
        }

        private fun filenameFromUrl(url: String): String {
            val segment = runCatching { URI(url).rawPath.substringAfterLast('/') }.getOrNull().orEmpty()
            val decoded = runCatching { URLDecoder.decode(segment, StandardCharsets.UTF_8.name()) }.getOrNull()
            return sanitizeFilename(decoded?.takeIf { it.isNotBlank() } ?: "download")
        }

        private fun filenameFromHeaders(disposition: String?, url: String): String {
            if (!disposition.isNullOrBlank()) {
                val encoded = Regex("filename\\*\\s*=\\s*UTF-8''([^;]+)", RegexOption.IGNORE_CASE)
                    .find(disposition)?.groupValues?.getOrNull(1)
                if (encoded != null) {
                    val decoded = runCatching { URLDecoder.decode(encoded.trim().trim('"'), "UTF-8") }.getOrNull()
                    if (!decoded.isNullOrBlank()) return sanitizeFilename(decoded)
                }
                val quoted = Regex("filename\\s*=\\s*\"([^\"]+)\"", RegexOption.IGNORE_CASE)
                    .find(disposition)?.groupValues?.getOrNull(1)
                if (!quoted.isNullOrBlank()) return sanitizeFilename(quoted)
            }
            return filenameFromUrl(url)
        }

        private fun sanitizeFilename(value: String): String {
            val safe = value.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_")
                .trim().trimStart('.').take(240)
            return safe.takeIf { it.isNotBlank() && it != "." && it != ".." } ?: "download"
        }

        private fun categoryFor(name: String, mime: String?): String {
            val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
            val type = mime?.substringBefore(';')?.lowercase(Locale.ROOT).orEmpty()
            return when {
                ext in setOf("mp4", "mkv", "mov", "avi", "webm", "m4v", "3gp", "mpeg", "mpg", "ts", "m3u8") || type.startsWith("video/") -> "Videos"
                ext in setOf("mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "alac", "aiff", "ape", "wv", "dsf", "dff") || type.startsWith("audio/") -> "Music"
                ext in setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff", "avif") || type.startsWith("image/") -> "Photos"
                ext == "apk" || type == "application/vnd.android.package-archive" -> "APK"
                ext in setOf("zip", "7z", "rar", "tar", "gz", "bz2", "xz", "zst", "iso") -> "Archives"
                ext in setOf("pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "odt", "ods", "odp", "csv") || type.startsWith("text/") || type.startsWith("application/pdf") -> "Documents"
                else -> "Others"
            }
        }
    }
}
