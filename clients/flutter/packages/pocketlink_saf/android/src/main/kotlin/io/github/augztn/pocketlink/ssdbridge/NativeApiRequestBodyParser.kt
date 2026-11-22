package io.github.augztn.pocketlink.ssdbridge

import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject
import java.io.File

/**
 * Reads multipart file uploads and JSON mutation payloads from NanoHTTPD sessions.
 *
 * Keep request-body parsing in one place so storage operations share identical
 * handling for POST, PUT, and PATCH requests.
 */
internal class NativeApiRequestBodyParser {
    fun multipartFile(session: NanoHTTPD.IHTTPSession): Pair<String, File>? {
        val files = HashMap<String, String>()
        session.parseBody(files)
        val tempPath = files["file"] ?: files["content"] ?: return null
        val name = session.parameters["file"]?.firstOrNull()
            ?: session.parameters["filename"]?.firstOrNull()
            ?: return null
        return name to File(tempPath)
    }

    fun jsonBody(session: NanoHTTPD.IHTTPSession): JSONObject? {
        val raw = if (session.method == NanoHTTPD.Method.PATCH) {
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

    private companion object {
        const val MAX_JSON_BODY_BYTES = 1024 * 1024
    }
}
