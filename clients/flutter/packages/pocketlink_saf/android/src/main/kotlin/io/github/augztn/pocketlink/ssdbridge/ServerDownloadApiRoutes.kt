package io.github.augztn.pocketlink.ssdbridge

import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject

/** Authenticated HTTP surface for persistent host-side URL downloads. */
internal class ServerDownloadApiRoutes(
    private val manager: ServerDownloadManager,
    private val parseJsonBody: (NanoHTTPD.IHTTPSession) -> JSONObject?,
    private val json: (JSONObject) -> NanoHTTPD.Response,
    private val bad: (String) -> NanoHTTPD.Response,
    private val notFound: (String) -> NanoHTTPD.Response
) {
    fun serve(session: NanoHTTPD.IHTTPSession): NanoHTTPD.Response? {
        if (!session.uri.startsWith("/api/downloads")) return null
        manager.start()
        if (session.uri == "/api/downloads" && session.method == NanoHTTPD.Method.GET) {
            return json(manager.list())
        }
        if (session.uri == "/api/downloads" && session.method == NanoHTTPD.Method.POST) {
            val body = parseJsonBody(session) ?: return bad("A JSON download request is required")
            val url = body.optString("url").trim()
            if (url.isBlank()) return bad("A download URL is required")
            return try {
                json(manager.enqueue(url, body.optString("directory").takeIf { it.isNotBlank() }))
            } catch (error: IllegalArgumentException) {
                bad(error.message ?: "Invalid download request")
            } catch (error: Exception) {
                bad(error.message ?: "Could not queue download")
            }
        }

        val segments = session.uri.removePrefix("/api/downloads/").split('/')
        if (segments.size !in 1..2 || segments[0].isBlank()) return notFound("Download job not found")
        val id = segments[0]
        if (segments.size == 1 && session.method == NanoHTTPD.Method.DELETE) {
            val deleteFile = session.parameters["delete_file"]?.firstOrNull()?.toBooleanStrictOrNull() ?: false
            return if (manager.remove(id, deleteFile)) {
                json(JSONObject().put("ok", true))
            } else notFound("Download job not found")
        }
        if (segments.size != 2 || session.method != NanoHTTPD.Method.POST) {
            return notFound("Download operation not found")
        }
        val result = when (segments[1]) {
            "pause" -> manager.pause(id)
            "resume" -> manager.resume(id)
            "cancel" -> manager.cancel(id)
            else -> return notFound("Download operation not found")
        }
        return result?.let(json) ?: notFound("Download job not found")
    }
}
