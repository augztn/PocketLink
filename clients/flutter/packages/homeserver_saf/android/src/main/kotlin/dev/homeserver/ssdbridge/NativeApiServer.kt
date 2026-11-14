package dev.homeserver.ssdbridge

import android.content.Context
import android.os.Environment
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.security.MessageDigest
import android.util.Base64

/**
 * Native replacement for the Termux FastAPI file/storage routes.
 * The listener is intentionally bound to all interfaces so Tailscale peers
 * can reach it; every non-health endpoint requires HTTP Basic authentication.
 */
internal class NativeApiServer(
    private val context: Context,
    private val credentials: ServerCredentials
) : NanoHTTPD("0.0.0.0", PORT) {
    private val prefs = context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE)
    private val internalRoot = Environment.getExternalStorageDirectory().canonicalFile

    override fun serve(session: IHTTPSession): Response {
        if (session.uri == "/health" && session.method == Method.GET) {
            return json(JSONObject().put("status", "ok").put("service", "homeserver-native"))
        }
        if (!authorized(session)) {
            return jsonError(Response.Status.UNAUTHORIZED, "Unauthorized")
                .apply { addHeader("WWW-Authenticate", "Basic realm=\"HomeServer\"") }
        }

        return try {
            val query = session.parms
            val path = query["path"].orEmpty()
            when {
                session.uri == "/api/files/" && session.method == Method.GET ->
                    listInternal(path)
                (session.uri == "/api/files/download" || session.uri == "/api/files/stream") &&
                    session.method == Method.GET -> serveInternalFile(path, session, session.uri.endsWith("/stream"))
                session.uri == "/api/files/upload" && session.method == Method.POST ->
                    uploadInternal(path, session)
                session.uri == "/api/files/mkdir" && session.method == Method.POST ->
                    mutateInternal(session, "mkdir")
                session.uri == "/api/files/rename" && session.method == Method.PATCH ->
                    mutateInternal(session, "rename")
                session.uri == "/api/files/item" && session.method == Method.DELETE ->
                    deleteInternal(path)
                session.uri == "/api/storage/volumes" && session.method == Method.GET ->
                    listVolumes()
                session.uri == "/api/storage/list" && session.method == Method.GET ->
                    listExternal(query["volume"], path)
                session.uri == "/api/storage/download" && session.method == Method.GET ->
                    serveExternalFile(query["volume"], path, session)
                session.uri == "/api/storage/upload" && session.method == Method.POST ->
                    uploadExternal(query["volume"], path, session)
                session.uri == "/api/storage/mkdir" && session.method == Method.POST ->
                    mutateExternal(session, "mkdir")
                session.uri == "/api/storage/rename" && session.method == Method.POST ->
                    mutateExternal(session, "rename")
                session.uri == "/api/storage/item" && session.method == Method.DELETE ->
                    deleteExternal(query["volume"], path)
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

    private fun listInternal(relative: String): Response {
        val directory = internalFile(relative) ?: return notFound("Folder not found")
        if (!directory.isDirectory) return bad("Not a directory")
        val items = JSONArray()
        (directory.listFiles() ?: emptyArray()).asSequence()
            .filter { !it.name.startsWith(".") }
            .sortedWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase(Locale.ROOT) }))
            .forEach { items.put(fileJson(it)) }
        return json(JSONObject().put("path", relative).put("items", items))
    }

    private fun serveInternalFile(relative: String, session: IHTTPSession, inline: Boolean): Response {
        val file = internalFile(relative) ?: return notFound("File not found")
        if (!file.isFile || !file.canRead()) return notFound("File not found")
        return fileResponse(file, session, inline)
    }

    private fun fileResponse(file: File, session: IHTTPSession, inline: Boolean): Response {
        val length = file.length()
        val mime = mimeFor(file.name)
        val range = session.headers["range"]
        val response: Response
        if (range.isNullOrBlank()) {
            response = newFixedLengthResponse(Response.Status.OK, mime, FileInputStream(file), length)
        } else {
            val bounds = parseRange(range, length) ?: return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Invalid byte range")
            val (start, end) = bounds
            val input = FileInputStream(file)
            var skipped = 0L
            while (skipped < start) {
                val count = input.skip(start - skipped)
                if (count <= 0L) { input.close(); return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Invalid byte range") }
                skipped += count
            }
            response = newFixedLengthResponse(
                Response.Status.PARTIAL_CONTENT, mime, input, end - start + 1
            ).apply { addHeader("Content-Range", "bytes $start-$end/$length") }
        }
        response.addHeader("Accept-Ranges", "bytes")
        response.addHeader("Content-Disposition", "${if (inline) "inline" else "attachment"}; filename*=UTF-8''${java.net.URLEncoder.encode(file.name, "UTF-8").replace("+", "%20")}")
        return response
    }

    private fun uploadInternal(relative: String, session: IHTTPSession): Response {
        val parent = internalFile(relative) ?: return notFound("Destination folder not found")
        if (!parent.isDirectory || !parent.canWrite()) return bad("Destination is not writable")
        val (name, temp) = multipartFile(session) ?: return bad("Multipart field 'file' is required")
        if (!validName(name)) { temp.delete(); return bad("Invalid filename") }
        val target = File(parent, name)
        if (target.exists()) { temp.delete(); return jsonError(Response.Status.CONFLICT, "An item with this name already exists") }
        val staging = File(parent, ".homeserver-upload-${UUID.randomUUID()}.part")
        return try {
            if (!temp.renameTo(staging)) temp.copyTo(staging, overwrite = false).also { temp.delete() }
            if (!staging.renameTo(target)) {
                staging.delete()
                jsonError(Response.Status.INTERNAL_ERROR, "Could not finalize uploaded file")
            } else json(JSONObject().put("ok", true).put("name", name))
        } finally {
            temp.delete()
            if (staging.exists()) staging.delete()
        }
    }

    private fun mutateInternal(session: IHTTPSession, operation: String): Response {
        val body = jsonBody(session) ?: return bad("Invalid JSON body")
        val relative = body.optString("path")
        val name = if (operation == "mkdir") body.optString("name") else body.optString("new_name")
        if (!validName(name)) return bad("Invalid name")

        if (operation == "mkdir") {
            val parent = internalFile(relative) ?: return notFound("Folder not found")
            if (!parent.isDirectory) return bad("Not a directory")
            val target = File(parent, name)
            if (target.exists()) return jsonError(Response.Status.CONFLICT, "Name already exists")
            return if (target.mkdir()) json(JSONObject().put("ok", true).put("name", name))
                else jsonError(Response.Status.INTERNAL_ERROR, "Could not create folder")
        }

        val oldFile = internalFile(relative) ?: return notFound("Item not found")
        if (oldFile == internalRoot) return bad("Cannot rename storage root")
        val parent = oldFile.parentFile ?: return bad("Invalid parent folder")
        val target = File(parent, name)
        if (target.exists()) return jsonError(Response.Status.CONFLICT, "Name already exists")
        return if (oldFile.renameTo(target)) json(JSONObject().put("ok", true).put("name", name))
            else jsonError(Response.Status.INTERNAL_ERROR, "Rename failed")
    }

    private fun deleteInternal(relative: String): Response {
        val file = internalFile(relative) ?: return notFound("Item not found")
        if (file == internalRoot) return bad("Cannot delete storage root")
        if (file.isDirectory && (file.list()?.isNotEmpty() == true)) return bad("Folder is not empty")
        return if (file.delete()) json(JSONObject().put("ok", true))
            else jsonError(Response.Status.INTERNAL_ERROR, "Delete failed")
    }

    private fun listVolumes(): Response {
        val items = JSONArray()
        listOf("usb1", "usb2").forEach { id ->
            val root = externalRoot(id)
            items.put(JSONObject()
                .put("id", id)
                .put("name", if (id == "usb1") "USB Storage 1" else "USB Storage 2")
                .put("available", root?.exists() == true)
                .put("writable", root?.canWrite() == true))
        }
        return json(JSONObject().put("items", items))
    }

    private fun listExternal(volume: String?, relative: String): Response {
        val root = externalRoot(volume) ?: return notFound("Storage permission not granted")
        val directory = resolveDocument(root, relative) ?: return notFound("Folder not found")
        if (!directory.isDirectory) return bad("Not a directory")
        val items = JSONArray()
        directory.listFiles().filter { !it.name.orEmpty().startsWith(".") }
            .sortedWith(compareBy<DocumentFile>({ !it.isDirectory }, { it.name.orEmpty().lowercase(Locale.ROOT) }))
            .forEach { item ->
                items.put(JSONObject().put("name", item.name ?: "")
                    .put("type", if (item.isDirectory) "directory" else "file")
                    .put("size", item.length()).put("modified", isoDate(item.lastModified())))
            }
        return json(JSONObject().put("path", relative).put("items", items))
    }

    private fun serveExternalFile(volume: String?, relative: String, session: IHTTPSession): Response {
        val root = externalRoot(volume) ?: return notFound("Storage permission not granted")
        val item = resolveDocument(root, relative) ?: return notFound("File not found")
        if (!item.isFile) return bad("Not a file")
        val input = context.contentResolver.openInputStream(item.uri) ?: return notFound("Cannot open file")
        val length = item.length()
        val range = session.headers["range"]
        if (range.isNullOrBlank()) {
            return newFixedLengthResponse(Response.Status.OK, item.type ?: mimeFor(item.name.orEmpty()), input, length)
                .apply { addHeader("Accept-Ranges", "bytes") }
        }
        val bounds = parseRange(range, length) ?: run {
            input.close()
            return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Invalid byte range")
        }
        val (start, end) = bounds
        var skipped = 0L
        while (skipped < start) {
            val count = input.skip(start - skipped)
            if (count <= 0L) { input.close(); return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Could not seek to byte range") }
            skipped += count
        }
        return newFixedLengthResponse(Response.Status.PARTIAL_CONTENT,
            item.type ?: mimeFor(item.name.orEmpty()), input, end - start + 1)
            .apply { addHeader("Accept-Ranges", "bytes"); addHeader("Content-Range", "bytes $start-$end/$length") }
    }

    private fun uploadExternal(volume: String?, relative: String, session: IHTTPSession): Response {
        val root = externalRoot(volume) ?: return notFound("Storage permission not granted")
        val parent = resolveDocument(root, relative) ?: return notFound("Destination folder not found")
        if (!parent.isDirectory) return bad("Destination is not a folder")
        val (name, temp) = multipartFile(session) ?: return bad("Multipart field 'file' is required")
        if (!validName(name)) { temp.delete(); return bad("Invalid filename") }
        if (parent.findFile(name) != null) { temp.delete(); return jsonError(Response.Status.CONFLICT, "Name already exists") }
        val staged = parent.createFile(mimeFor(name), ".homeserver-upload-${UUID.randomUUID()}.part")
            ?: run { temp.delete(); return jsonError(Response.Status.INTERNAL_ERROR, "Could not stage upload") }
        return try {
            context.contentResolver.openOutputStream(staged.uri, "wt")?.use { output ->
                temp.inputStream().use { input -> input.copyTo(output) }
            } ?: return jsonError(Response.Status.INTERNAL_ERROR, "Cannot write file")
            if (!staged.renameTo(name)) jsonError(Response.Status.INTERNAL_ERROR, "Could not finalize uploaded file")
            else json(JSONObject().put("ok", true).put("name", name))
        } finally {
            temp.delete()
            if (staged.exists()) staged.delete()
        }
    }

    private fun mutateExternal(session: IHTTPSession, operation: String): Response {
        val body = jsonBody(session) ?: return bad("Invalid JSON body")
        val root = externalRoot(body.optString("volume")) ?: return notFound("Storage permission not granted")
        val relative = body.optString("path")
        val name = if (operation == "mkdir") body.optString("name") else body.optString("new_name")
        if (!validName(name)) return bad("Invalid name")
        val target: DocumentFile
        if (operation == "mkdir") {
            val parent = resolveDocument(root, relative) ?: return notFound("Folder not found")
            if (parent.findFile(name) != null) return jsonError(Response.Status.CONFLICT, "Name already exists")
            target = parent.createDirectory(name) ?: return jsonError(Response.Status.INTERNAL_ERROR, "Could not create folder")
        } else {
            target = resolveDocument(root, relative) ?: return notFound("Item not found")
            if (target.parentFile?.findFile(name) != null) return jsonError(Response.Status.CONFLICT, "Name already exists")
            if (!target.renameTo(name)) return jsonError(Response.Status.INTERNAL_ERROR, "Rename failed")
        }
        return json(JSONObject().put("ok", true).put("name", target.name ?: name))
    }

    private fun deleteExternal(volume: String?, relative: String): Response {
        val root = externalRoot(volume) ?: return notFound("Storage permission not granted")
        if (relative.isBlank()) return bad("Cannot delete storage root")
        val item = resolveDocument(root, relative) ?: return notFound("Item not found")
        return if (item.delete()) json(JSONObject().put("ok", true))
            else jsonError(Response.Status.INTERNAL_ERROR, "Delete failed")
    }

    private fun internalFile(relative: String): File? {
        if (relative.isBlank()) return internalRoot
        val parts = relative.split('/')
        if (parts.any { !validName(it) }) return null
        val target = File(internalRoot, relative).canonicalFile
        val prefix = internalRoot.path + File.separator
        return if (target.path == internalRoot.path || target.path.startsWith(prefix)) target else null
    }

    private fun externalRoot(volume: String?): DocumentFile? {
        val key = when (volume) { "usb1" -> "usb1"; "usb2" -> "usb2"; else -> return null }
        val uri = prefs.getString(key, null)?.let(Uri::parse) ?: return null
        return DocumentFile.fromTreeUri(context, uri)
    }

    private fun resolveDocument(root: DocumentFile, relative: String): DocumentFile? {
        var current = root
        if (relative.isBlank()) return current
        for (part in relative.split('/')) {
            if (!validName(part)) return null
            current = current.findFile(part) ?: return null
        }
        return current
    }

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
        val files = HashMap<String, String>()
        session.parseBody(files)
        val raw = files["postData"]?.let { File(it).readText() }
            ?: files["content"]?.let { File(it).readText() }
            ?: return null
        return try { JSONObject(raw) } catch (_: Exception) { null }
    }

    private fun fileJson(file: File): JSONObject = JSONObject()
        .put("name", file.name)
        .put("type", if (file.isDirectory) "directory" else "file")
        .put("size", if (file.isFile) file.length() else 0L)
        .put("modified", isoDate(file.lastModified()))

    private fun parseRange(value: String, length: Long): Pair<Long, Long>? {
        if (length <= 0L) return null
        val match = Regex("bytes=(\\d*)-(\\d*)").matchEntire(value) ?: return null
        val first = match.groupValues[1]
        val last = match.groupValues[2]
        val start: Long
        val end: Long
        if (first.isEmpty()) {
            val suffix = last.toLongOrNull()?.takeIf { it > 0L } ?: return null
            start = (length - suffix).coerceAtLeast(0L)
            end = length - 1
        } else {
            start = first.toLongOrNull() ?: return null
            end = (last.toLongOrNull() ?: (length - 1)).coerceAtMost(length - 1)
        }
        if (start < 0L || start >= length || end < start) return null
        return start to end
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

    private fun mimeFor(name: String): String = when (name.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
        "jpg", "jpeg" -> "image/jpeg"; "png" -> "image/png"; "gif" -> "image/gif"; "webp" -> "image/webp"
        "mp3" -> "audio/mpeg"; "m4a", "mp4" -> "video/mp4"; "aac" -> "audio/aac"
        "flac" -> "audio/flac"; "ogg", "opus" -> "audio/ogg"; "wav" -> "audio/wav"
        "mkv" -> "video/x-matroska"; "pdf" -> "application/pdf"; "txt" -> "text/plain"
        else -> "application/octet-stream"
    }

    private fun bad(message: String) = jsonError(Response.Status.BAD_REQUEST, message)
    private fun notFound(message: String) = jsonError(Response.Status.NOT_FOUND, message)
    private fun jsonError(status: Response.Status, message: String) =
        json(JSONObject().put("detail", message), status)
    private fun json(value: JSONObject, status: Response.Status = Response.Status.OK) =
        newFixedLengthResponse(status, "application/json; charset=utf-8", value.toString())

    companion object {
        const val PORT = 8000
        const val USERNAME = "admin"
    }
}
