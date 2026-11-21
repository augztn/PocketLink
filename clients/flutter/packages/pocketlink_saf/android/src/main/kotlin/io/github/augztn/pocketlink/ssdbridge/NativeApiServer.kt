package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.os.Environment
import android.os.Build
import android.os.StatFs
import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import android.util.Base64

/**
 * Native replacement for the Termux FastAPI file/storage routes.
 * The listener is bound to all interfaces for Tailscale reachability, while
 * NetworkAccessPolicy rejects cleartext peers outside loopback/Tailscale.
 * Every route except health requires HTTP Basic authentication.
 */
internal class NativeApiServer(
    private val context: Context,
    private val credentials: ServerCredentials,
    listenPort: Int = PORT,
    bindHost: String = "0.0.0.0",
    internalRootOverride: File? = null
) : NanoHTTPD(bindHost, listenPort) {
    private val prefs = context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE)
    private val externalStorage = ExternalStorageAccess(context, prefs, ::validName)
    private val externalOperations by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        ExternalStorageOperations(
            context = context,
            prefs = prefs,
            storage = externalStorage,
            parseMultipart = ::multipartFile,
            parseJsonBody = ::jsonBody,
            isValidName = ::validName,
            mimeFor = ::mimeFor,
            formatDate = ::isoDate,
            json = { value -> json(value) },
            bad = ::bad,
            notFound = ::notFound,
            error = ::jsonError,
            markMediaIndexDirty = ::markMediaIndexDirty,
            mutationLock = FILE_MUTATION_LOCK
        )
    }
    private val fileResponseOperations by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        NativeFileResponseOperations(
            context = context,
            externalStorage = externalStorage,
            error = ::jsonError,
            notFound = ::notFound,
            bad = ::bad
        )
    }
    private val systemTelemetry by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        SystemTelemetryReader(context)
    }
    // Keep server startup and health checks independent of external-storage availability.
    private val internalRoot by lazy(LazyThreadSafetyMode.NONE) {
        (internalRootOverride ?: Environment.getExternalStorageDirectory()).canonicalFile
    }
    private val internalStorage by lazy(LazyThreadSafetyMode.NONE) {
        InternalStorageAccess(internalRoot, ::validName)
    }
    private val internalOperations by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        InternalStorageOperations(
            root = { internalRoot },
            resolve = ::internalFile,
            isValidName = ::validName,
            parseMultipart = ::multipartFile,
            parseJsonBody = ::jsonBody,
            fileJson = ::fileJson,
            fileResponse = ::fileResponse,
            json = { value -> json(value) },
            error = { status, message -> jsonError(status, message) },
            markMediaIndexDirty = ::markMediaIndexDirty,
            mutationLock = FILE_MUTATION_LOCK
        )
    }
    private val mediaIndexDelegate = lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        MediaIndexScanner(
            context,
            { internalRoot },
            {
                val ids = linkedSetOf<String>()
                prefs.all.keys.filter { it.startsWith("volume_uri_") }.forEach {
                    ids.add(it.removePrefix("volume_uri_"))
                }
                if (prefs.getString("usb1", null) != null) ids.add("usb1")
                if (prefs.getString("usb2", null) != null) ids.add("usb2")
                ids.mapNotNull { id -> externalStorage.root(id)?.let { root -> id to root } }
            }
        )
    }
    private val mediaIndex by mediaIndexDelegate
    private val fileStorageRoutes by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        NativeFileStorageApiRoutes(
            listInternal = ::listInternal,
            serveInternalFile = ::serveInternalFile,
            uploadInternal = ::uploadInternal,
            mutateInternal = ::mutateInternal,
            deleteInternal = ::deleteInternal,
            listVolumes = ::listVolumes,
            listExternal = ::listExternal,
            serveExternalFile = ::serveExternalFile,
            uploadExternal = ::uploadExternal,
            mutateExternal = ::mutateExternal,
            deleteExternal = ::deleteExternal,
            videoMetadata = ::videoMetadata,
            videoThumbnail = ::videoThumbnail
        )
    }
    private val mediaIndexRoutes by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        MediaIndexApiRoutes(
            mediaIndex,
            jsonResponse = { value -> json(value) },
            badRequest = { message -> bad(message) },
            formatDate = { timestamp -> isoDate(timestamp) }
        )
    }

    private fun markMediaIndexDirty() {
        if (mediaIndexDelegate.isInitialized()) mediaIndex.markDirty()
    }

    fun ensureMediaIndexStarted() = mediaIndex.ensureStarted()

    fun closeMediaIndex() {
        if (mediaIndexDelegate.isInitialized()) mediaIndex.close()
    }

    fun mediaIndexStatus(): String {
        mediaIndex.ensureStarted()
        return mediaIndex.status().toString()
    }

    fun mediaIndexSettings(): String = mediaIndex.automaticSettings().toString()

    fun updateMediaIndexSettings(
        enabled: Boolean,
        intervalMinutes: Int,
        scanOnStartup: Boolean,
        scanOnStorageChange: Boolean
    ): String = mediaIndex.configureAutomaticScanning(
        enabled, intervalMinutes, scanOnStartup, scanOnStorageChange
    ).toString()

    fun retryMediaIndex(): String {
        mediaIndex.retryFailedScan()
        return mediaIndex.status().toString()
    }

    fun runScheduledMediaScanCheck() = mediaIndex.runScheduledScanCheck()

    fun onStorageChanged(connected: Boolean, volumeId: String? = null) =
        mediaIndex.onStorageChanged(connected, volumeId)

    fun refreshMediaIndex(): String {
        mediaIndex.requestScan(force = true, trigger = "manual")
        return mediaIndex.status().toString()
    }

    override fun serve(session: IHTTPSession): Response {
        // The native listener is cleartext HTTP. Trust only loopback or peers
        // arriving through Tailscale's encrypted WireGuard address ranges.
        if (!NetworkAccessPolicy.allowsCleartextPeer(session.remoteIpAddress)) {
            return jsonError(
                Response.Status.FORBIDDEN,
                "Cleartext access is limited to localhost and Tailscale peers"
            )
        }
        if (session.uri == "/health" && session.method == Method.GET) {
            return json(JSONObject().put("status", "ok").put("service", "pocketlink-native"))
        }
        if (!authorized(session)) {
            return jsonError(Response.Status.UNAUTHORIZED, "Unauthorized")
                .apply { addHeader("WWW-Authenticate", "Basic realm=\"PocketLink\"") }
        }

        return try {
            val query = session.parameters.mapValues { (_, values) -> values.firstOrNull().orEmpty() }
            val path = query["path"].orEmpty()
            if (session.uri.startsWith("/api/index/")) {
                mediaIndexRoutes.serve(session, query)?.let { return it }
            }
            fileStorageRoutes.serve(session, query, path)?.let { return it }
            when {
                session.uri == "/api/system/telemetry" && session.method == Method.GET ->
                    json(systemTelemetry.snapshot())
                else -> jsonError(Response.Status.NOT_FOUND, "Endpoint not found")
            }
        } catch (error: SecurityException) {
            jsonError(Response.Status.FORBIDDEN, "Android storage permission was revoked")
        } catch (error: Exception) {
            jsonError(Response.Status.INTERNAL_ERROR, error.message ?: "Storage operation failed")
        }
    }

    private fun authorized(session: IHTTPSession): Boolean {
        val header = session.headers["authorization"] ?: return false
        if (!header.startsWith("Basic ", ignoreCase = true)) return false
        val decoded = try {
            String(Base64.decode(header.substringAfter(' ').trim(), Base64.DEFAULT), Charsets.UTF_8)
        } catch (_: IllegalArgumentException) {
            return false
        }
        val separator = decoded.indexOf(':')
        if (separator <= 0) return false
        val username = decoded.substring(0, separator)
        if (username != USERNAME) return false
        return credentials.verify(decoded.substring(separator + 1).toCharArray())
    }

    private fun listInternal(relative: String): Response = internalOperations.list(relative)

    private fun serveInternalFile(relative: String, session: IHTTPSession, inline: Boolean): Response =
        internalOperations.serveFile(relative, session, inline)

    private fun fileResponse(file: File, session: IHTTPSession, inline: Boolean): Response =
        fileResponseOperations.serveInternalFile(file, session, inline)

    private fun uploadInternal(relative: String, session: IHTTPSession): Response =
        internalOperations.upload(relative, session)

    private fun mutateInternal(session: IHTTPSession, operation: String): Response =
        internalOperations.mutate(session, operation)

    private fun deleteInternal(relative: String): Response = internalOperations.delete(relative)

    private fun listVolumes(): Response = externalOperations.listVolumes()

    private fun listExternal(volume: String?, relative: String): Response =
        externalOperations.list(volume, relative)

    private fun serveExternalFile(volume: String?, relative: String, session: IHTTPSession): Response =
        fileResponseOperations.serveExternalFile(volume, relative, session)

    private fun uploadExternal(volume: String?, relative: String, session: IHTTPSession): Response =
        externalOperations.upload(volume, relative, session)

    private fun mutateExternal(session: IHTTPSession, operation: String): Response =
        externalOperations.mutate(session, operation)

    private fun deleteExternal(volume: String?, relative: String): Response =
        externalOperations.delete(volume, relative)

    private val mediaMetadataOperations by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        NativeMediaMetadataOperations(
            context = context,
            externalStorage = externalStorage,
            internalFile = ::internalFile,
            bad = ::bad,
            notFound = ::notFound,
            error = ::jsonError,
            json = { value -> json(value) },
            fixedResponse = { mime, bytes, cacheControl ->
                newFixedLengthResponse(Response.Status.OK, mime, ByteArrayInputStream(bytes), bytes.size.toLong())
                    .apply { addHeader("Cache-Control", cacheControl) }
            }
        )
    }

    private fun videoMetadata(volume: String?, relative: String): Response =
        mediaMetadataOperations.videoMetadata(volume, relative)

    private fun videoThumbnail(volume: String?, relative: String): Response =
        mediaMetadataOperations.videoThumbnail(volume, relative)

    private fun internalFile(relative: String): File? = internalStorage.resolve(relative)

    private fun multipartFile(session: IHTTPSession): Pair<String, File>? {
        val files = HashMap<String, String>()
        session.parseBody(files)
        val tempPath = files["file"] ?: files["content"] ?: return null
        val name = session.parameters["file"]?.firstOrNull()
            ?: session.parameters["filename"]?.firstOrNull()
            ?: return null
        return name to File(tempPath)
    }

    private fun jsonBody(session: IHTTPSession): JSONObject? {
        val raw = if (session.method == Method.PATCH) {
            // NanoHTTPD's parseBody consumes PATCH payloads but only exposes parsed
            // content for POST and PUT. Read the bounded JSON body directly instead.
            val contentLength = session.headers["content-length"]?.toLongOrNull()
                ?: return null
            if (contentLength <= 0 || contentLength > MAX_JSON_BODY_BYTES) return null
            val bytes = ByteArray(contentLength.toInt())
            var offset = 0
            while (offset < bytes.size) {
                val count = session.inputStream.read(bytes, offset, bytes.size - offset)
                if (count < 0) return null
                offset += count
            }
            bytes.toString(Charsets.UTF_8)
        } else {
            val files = HashMap<String, String>()
            session.parseBody(files)
            files["postData"]?.let { File(it).readText() }
                ?: files["content"]?.let { File(it).readText() }
                ?: return null
        }
        return try { JSONObject(raw) } catch (_: Exception) { null }
    }

    private fun fileJson(file: File): JSONObject {
        val value = JSONObject()
            .put("name", file.name)
            .put("type", if (file.isDirectory) "directory" else "file")
            .put("size", if (file.isFile) file.length() else 0L)
            .put("modified", isoDate(file.lastModified()))
        // Filesystem birth time is not available on every Android filesystem.
        // Only publish it when the provider supplies a valid value.
        if (file.isFile && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val created = java.nio.file.Files.readAttributes(
                    file.toPath(),
                    java.nio.file.attribute.BasicFileAttributes::class.java
                ).creationTime().toMillis()
                if (created > 0L) value.put("created", isoDate(created))
            } catch (_: Exception) {
                // Some Android/FUSE filesystems do not expose birth time.
            }
        }
        return value
    }

    private fun validName(value: String): Boolean =
        value.isNotBlank() && value != "." && value != ".." &&
            !value.startsWith(".") && !value.contains('/') && !value.contains('\\') &&
            !value.any { it.code < 32 }

    private fun isoDate(timestamp: Long): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date(timestamp))
    }

    private fun bad(message: String) = jsonError(Response.Status.BAD_REQUEST, message)
    private fun notFound(message: String) = jsonError(Response.Status.NOT_FOUND, message)
    private fun jsonError(status: Response.Status, message: String) =
        json(JSONObject().put("detail", message), status)
    private fun json(value: JSONObject, status: Response.Status = Response.Status.OK) =
        newFixedLengthResponse(status, "application/json; charset=utf-8", value.toString())

    companion object {
        private const val MAX_JSON_BODY_BYTES = 1024 * 1024
        const val PORT = 8000
        const val USERNAME = "admin"
        private const val STREAM_BUFFER_SIZE = 64 * 1024
        private val FILE_MUTATION_LOCK = Any()
    }
}