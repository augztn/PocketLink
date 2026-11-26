package io.github.augztn.pocketlink.ssdbridge

import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject

/**
 * Owns the HTTP contract for media-index status, settings, scan, and query endpoints.
 * Storage and file routes remain in [NativeApiServer].
 */
internal class MediaIndexApiRoutes(
    private val mediaIndex: MediaIndexScanner,
    private val jsonResponse: (JSONObject) -> NanoHTTPD.Response,
    private val badRequest: (String) -> NanoHTTPD.Response,
    private val formatDate: (Long) -> String
) {
    fun serve(
        session: NanoHTTPD.IHTTPSession,
        query: Map<String, String>
    ): NanoHTTPD.Response? {
        return when {
            session.uri == "/api/index/status" && session.method == NanoHTTPD.Method.GET -> {
                mediaIndex.ensureStarted()
                jsonResponse(mediaIndex.status())
            }
            session.uri == "/api/index/settings" && session.method == NanoHTTPD.Method.GET ->
                jsonResponse(JSONObject(mediaIndex.automaticSettings().toString()))
            session.uri == "/api/index/settings" && session.method == NanoHTTPD.Method.POST -> {
                val enabled = query["enabled"]?.toBooleanStrictOrNull()
                    ?: return badRequest("A valid automatic scanning enabled value is required")
                val interval = query["interval_minutes"]?.toIntOrNull()
                    ?: return badRequest("A valid scan interval is required")
                if (interval !in 15..1440) {
                    return badRequest("Scan interval must be between 15 and 1440 minutes")
                }
                val current = mediaIndex.automaticSettings()
                val scanOnStartup = query["scan_on_startup"]?.toBooleanStrictOrNull()
                    ?: current.optBoolean("scan_on_startup", true)
                val scanOnStorageChange = query["scan_on_storage_change"]?.toBooleanStrictOrNull()
                    ?: current.optBoolean("scan_on_storage_change", true)
                jsonResponse(JSONObject(mediaIndex.configureAutomaticScanning(
                    enabled, interval, scanOnStartup, scanOnStorageChange
                ).toString()))
            }
            session.uri == "/api/index/retry" && session.method == NanoHTTPD.Method.POST -> {
                mediaIndex.retryFailedScan()
                jsonResponse(mediaIndex.status())
            }
            session.uri == "/api/index/scan" && session.method == NanoHTTPD.Method.POST -> {
                mediaIndex.requestScan(force = true, trigger = "manual")
                jsonResponse(mediaIndex.status())
            }
            session.uri == "/api/index/media" && session.method == NanoHTTPD.Method.GET -> {
                mediaIndex.ensureStarted()
                val category = query["category"]?.takeIf { it in MEDIA_CATEGORIES }
                    ?: return badRequest("Invalid media category")
                val limit = query["limit"]?.toIntOrNull()?.coerceIn(1, 500) ?: DEFAULT_PAGE_SIZE
                val offset = query["offset"]?.toIntOrNull()?.coerceAtLeast(0) ?: 0
                val items = JSONArray()
                mediaIndex.media(category, query["q"].orEmpty(), limit, offset).forEach { item ->
                    items.put(JSONObject()
                        .put("volume", item.volume)
                        .put("path", item.path)
                        .put("name", item.name)
                        .put("type", item.type)
                        .put("size", item.size)
                        .put("modified", formatDate(item.modified))
                        .put("mime", item.mime)
                        .put("category", item.category)
                        .put("title", item.title)
                        .put("artist", item.artist)
                        .put("album", item.album)
                        .put("duration_ms", item.durationMs)
                        .put("metadata_scanned", item.metadataScanned))
                }
                jsonResponse(JSONObject().put("items", items).put("status", mediaIndex.status()))
            }
            session.uri == "/api/index/files" && session.method == NanoHTTPD.Method.GET -> {
                mediaIndex.ensureStarted()
                val limit = query["limit"]?.toIntOrNull()?.coerceIn(1, 500) ?: DEFAULT_PAGE_SIZE
                val offset = query["offset"]?.toIntOrNull()?.coerceAtLeast(0) ?: 0
                val items = JSONArray()
                mediaIndex.files(query["q"].orEmpty(), limit, offset).forEach { item ->
                    items.put(JSONObject()
                        .put("volume", item.volume)
                        .put("path", item.path)
                        .put("name", item.name)
                        .put("type", item.type)
                        .put("size", item.size)
                        .put("modified", formatDate(item.modified))
                        .put("mime", item.mime))
                }
                jsonResponse(JSONObject().put("items", items).put("status", mediaIndex.status()))
            }
            else -> null
        }
    }

    private companion object {
        const val DEFAULT_PAGE_SIZE = 100
        val MEDIA_CATEGORIES = setOf("music", "video", "photo")
    }
}
