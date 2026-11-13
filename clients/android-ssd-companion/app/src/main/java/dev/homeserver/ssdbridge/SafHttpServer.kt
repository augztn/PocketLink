package dev.homeserver.ssdbridge

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

class SafHttpServer(private val context: Context, private val token: String) : NanoHTTPD("127.0.0.1", 8765) {
    private val prefs = context.getSharedPreferences("ssd-bridge", Context.MODE_PRIVATE)

    override fun serve(session: IHTTPSession): Response {
        if (session.uri == "/health" && session.method == Method.GET) {
            return json(JSONObject().put("status", "ok").put("service", "saf-bridge"))
        }
        val supplied = session.headers["authorization"] ?: ""
        if (token.isBlank() || !MessageDigest.isEqual(
                supplied.toByteArray(Charsets.UTF_8),
                "Bearer $token".toByteArray(Charsets.UTF_8)
            )) return text(Response.Status.UNAUTHORIZED, "Unauthorized")

        return try {
            val q = session.parms
            if (session.uri == "/v1/volumes" && session.method == Method.GET) return volumes()
            val volume = q["volume"] ?: return bad("volume is required")
            val root = rootFor(volume) ?: return jsonError(Response.Status.NOT_FOUND, "Storage permission not granted")
            val path = q["path"].orEmpty()
            when {
                session.uri == "/v1/list" && session.method == Method.GET -> {
                    val dir = resolve(root, path) ?: return jsonError(Response.Status.NOT_FOUND, "Folder not found")
                    if (!dir.isDirectory) return jsonError(Response.Status.BAD_REQUEST, "Not a directory")
                    val items = JSONArray()
                    dir.listFiles().forEach { file ->
                        items.put(JSONObject()
                            .put("name", file.name ?: "")
                            .put("type", if (file.isDirectory) "directory" else "file")
                            .put("size", file.length())
                            .put("modified", file.lastModified()))
                    }
                    json(JSONObject().put("volume", volume).put("path", path).put("items", items))
                }
                session.uri == "/v1/read" && session.method == Method.GET -> {
                    val file = resolve(root, path) ?: return jsonError(Response.Status.NOT_FOUND, "File not found")
                    if (!file.isFile) return jsonError(Response.Status.BAD_REQUEST, "Not a file")
                    val length = file.length()
                    val range = session.headers["range"]
                    val input = context.contentResolver.openInputStream(file.uri)
                        ?: return jsonError(Response.Status.INTERNAL_ERROR, "Cannot open file")
                    if (range == null) {
                        return newFixedLengthResponse(
                            Response.Status.OK, file.type ?: "application/octet-stream", input, length
                        ).apply { addHeader("Accept-Ranges", "bytes") }
                    }
                    val match = Regex("bytes=(\\d*)-(\\d*)").matchEntire(range)
                        ?: run { input.close(); return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Invalid byte range") }
                    if (length <= 0L) {
                        input.close()
                        return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Range outside empty file")
                    }
                    val startText = match.groupValues[1]
                    val endText = match.groupValues[2]
                    val start: Long
                    val requestedEnd: Long
                    if (startText.isEmpty()) {
                        val suffixLength = endText.toLongOrNull()
                        if (suffixLength == null || suffixLength <= 0L) {
                            input.close()
                            return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Invalid suffix range")
                        }
                        start = (length - suffixLength).coerceAtLeast(0L)
                        requestedEnd = length - 1
                    } else {
                        start = startText.toLongOrNull() ?: -1L
                        requestedEnd = endText.toLongOrNull() ?: (length - 1)
                    }
                    if (start < 0L || start >= length || requestedEnd < start) {
                        input.close()
                        return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Range outside file")
                    }
                    val end = minOf(requestedEnd, length - 1)
                    var skipped = 0L
                    while (skipped < start) {
                        val count = input.skip(start - skipped)
                        if (count <= 0) break
                        skipped += count
                    }
                    if (skipped != start) {
                        input.close()
                        return jsonError(Response.Status.RANGE_NOT_SATISFIABLE, "Could not seek to byte range")
                    }
                    return newFixedLengthResponse(
                        Response.Status.PARTIAL_CONTENT, file.type ?: "application/octet-stream",
                        input, end - start + 1
                    ).apply {
                        addHeader("Accept-Ranges", "bytes")
                        addHeader("Content-Range", "bytes $start-$end/$length")
                    }
                }
                session.uri == "/v1/write" && session.method == Method.PUT -> {
                    val name = path.substringAfterLast('/')
                    if (!validName(name)) return bad("Invalid filename")
                    val parentPath = path.substringBeforeLast('/', "")
                    val parent = resolve(root, parentPath) ?: return jsonError(Response.Status.NOT_FOUND, "Parent folder not found")
                    if (!parent.isDirectory) return bad("Parent is not a folder")
                    val existing = parent.findFile(name)
                    if (existing != null && existing.isDirectory) return bad("A folder already uses this name")
                    val target = existing ?: parent.createFile(mimeFor(name), name)
                        ?: return jsonError(Response.Status.INTERNAL_ERROR, "Could not create file")
                    val output = context.contentResolver.openOutputStream(target.uri, "wt")
                        ?: return jsonError(Response.Status.INTERNAL_ERROR, "Cannot write file")
                    session.inputStream.use { input -> output.use { input.copyTo(it) } }
                    json(JSONObject().put("ok", true).put("name", name))
                }
                session.uri == "/v1/mkdir" && session.method == Method.POST -> {
                    val name = q["name"] ?: return bad("name is required")
                    if (!validName(name)) return bad("Invalid folder name")
                    val parent = resolve(root, path) ?: return jsonError(Response.Status.NOT_FOUND, "Parent folder not found")
                    if (parent.findFile(name) != null) return bad("Name already exists")
                    val created = parent.createDirectory(name) ?: return jsonError(Response.Status.INTERNAL_ERROR, "Could not create folder")
                    json(JSONObject().put("ok", true).put("name", created.name))
                }
                session.uri == "/v1/rename" && session.method == Method.POST -> {
                    val name = q["name"] ?: return bad("name is required")
                    if (!validName(name)) return bad("Invalid name")
                    val item = resolve(root, path) ?: return jsonError(Response.Status.NOT_FOUND, "Item not found")
                    if (!item.renameTo(name)) return jsonError(Response.Status.INTERNAL_ERROR, "Rename failed")
                    json(JSONObject().put("ok", true).put("name", name))
                }
                session.uri == "/v1/item" && session.method == Method.DELETE -> {
                    val item = resolve(root, path) ?: return jsonError(Response.Status.NOT_FOUND, "Item not found")
                    if (!item.delete()) return jsonError(Response.Status.INTERNAL_ERROR, "Delete failed")
                    json(JSONObject().put("ok", true))
                }
                else -> jsonError(Response.Status.NOT_FOUND, "Unknown endpoint")
            }
        } catch (error: SecurityException) {
            jsonError(Response.Status.FORBIDDEN, "Android storage permission was revoked")
        } catch (error: Exception) {
            jsonError(Response.Status.INTERNAL_ERROR, error.message ?: "Storage operation failed")
        }
    }

    private fun rootFor(id: String): DocumentFile? {
        val key = when (id) { "usb1" -> "usb1"; "usb2" -> "usb2"; else -> return null }
        val value = prefs.getString(key, null) ?: return null
        return DocumentFile.fromTreeUri(context, Uri.parse(value))
    }

    private fun resolve(root: DocumentFile, path: String): DocumentFile? {
        var current = root
        if (path.isBlank()) return current
        for (part in path.split('/')) {
            if (!validName(part)) return null
            current = current.findFile(part) ?: return null
        }
        return current
    }

    private fun validName(value: String): Boolean =
        value.isNotBlank() && value != "." && value != ".." &&
            !value.contains('/') && !value.contains('\\') &&
            !value.any { it.code < 32 }

    private fun mimeFor(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "mp3" -> "audio/mpeg"; "m4a" -> "audio/mp4"; "flac" -> "audio/flac"
        "mp4" -> "video/mp4"; "mkv" -> "video/x-matroska"; "pdf" -> "application/pdf"
        else -> "application/octet-stream"
    }

    private fun volumes(): Response {
        val result = JSONArray()
        listOf("usb1", "usb2").forEach { id ->
            val root = rootFor(id)
            result.put(JSONObject().put("id", id).put("name", if (id == "usb1") "USB Storage 1" else "USB Storage 2")
                .put("available", root != null && root.exists()).put("writable", root?.canWrite() == true))
        }
        return json(JSONObject().put("items", result))
    }

    private fun bad(message: String) = jsonError(Response.Status.BAD_REQUEST, message)
    private fun jsonError(status: Response.Status, message: String) = json(JSONObject().put("detail", message), status)
    private fun json(value: JSONObject, status: Response.Status = Response.Status.OK) =
        newFixedLengthResponse(status, "application/json; charset=utf-8", value.toString())
    private fun text(status: Response.Status, value: String) =
        newFixedLengthResponse(status, "text/plain; charset=utf-8", value)
}
