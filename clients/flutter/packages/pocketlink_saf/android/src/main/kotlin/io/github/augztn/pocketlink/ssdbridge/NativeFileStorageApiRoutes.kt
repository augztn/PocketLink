package io.github.augztn.pocketlink.ssdbridge

import fi.iki.elonen.NanoHTTPD

/**
 * Dispatches file, removable-storage, and media-metadata API requests.
 * Storage operations remain owned by NativeApiServer until their dependencies
 * can be extracted behind a dedicated storage service.
 */
internal class NativeFileStorageApiRoutes(
    private val listInternal: (String) -> NanoHTTPD.Response,
    private val serveInternalFile: (String, NanoHTTPD.IHTTPSession, Boolean) -> NanoHTTPD.Response,
    private val uploadInternal: (String, NanoHTTPD.IHTTPSession) -> NanoHTTPD.Response,
    private val mutateInternal: (NanoHTTPD.IHTTPSession, String) -> NanoHTTPD.Response,
    private val deleteInternal: (String) -> NanoHTTPD.Response,
    private val listVolumes: () -> NanoHTTPD.Response,
    private val listExternal: (String?, String) -> NanoHTTPD.Response,
    private val serveExternalFile: (String?, String, NanoHTTPD.IHTTPSession) -> NanoHTTPD.Response,
    private val uploadExternal: (String?, String, NanoHTTPD.IHTTPSession) -> NanoHTTPD.Response,
    private val mutateExternal: (NanoHTTPD.IHTTPSession, String) -> NanoHTTPD.Response,
    private val deleteExternal: (String?, String) -> NanoHTTPD.Response,
    private val videoMetadata: (String?, String) -> NanoHTTPD.Response,
    private val videoThumbnail: (String?, String) -> NanoHTTPD.Response
) {
    fun serve(
        session: NanoHTTPD.IHTTPSession,
        query: Map<String, String>,
        path: String
    ): NanoHTTPD.Response? = when {
        session.uri == "/api/files/" && session.method == NanoHTTPD.Method.GET ->
            listInternal(path)
        (session.uri == "/api/files/download" || session.uri == "/api/files/stream") &&
            session.method == NanoHTTPD.Method.GET ->
            serveInternalFile(path, session, session.uri.endsWith("/stream"))
        session.uri == "/api/files/upload" && session.method == NanoHTTPD.Method.POST ->
            uploadInternal(path, session)
        session.uri == "/api/files/mkdir" && session.method == NanoHTTPD.Method.POST ->
            mutateInternal(session, "mkdir")
        session.uri == "/api/files/rename" && session.method == NanoHTTPD.Method.PATCH ->
            mutateInternal(session, "rename")
        session.uri == "/api/files/item" && session.method == NanoHTTPD.Method.DELETE ->
            deleteInternal(path)
        session.uri == "/api/storage/volumes" && session.method == NanoHTTPD.Method.GET ->
            listVolumes()
        session.uri == "/api/storage/list" && session.method == NanoHTTPD.Method.GET ->
            listExternal(query["volume"], path)
        session.uri == "/api/storage/download" && session.method == NanoHTTPD.Method.GET ->
            serveExternalFile(query["volume"], path, session)
        session.uri == "/api/storage/upload" && session.method == NanoHTTPD.Method.POST ->
            uploadExternal(query["volume"], path, session)
        session.uri == "/api/storage/mkdir" && session.method == NanoHTTPD.Method.POST ->
            mutateExternal(session, "mkdir")
        session.uri == "/api/storage/rename" && session.method == NanoHTTPD.Method.POST ->
            mutateExternal(session, "rename")
        session.uri == "/api/storage/item" && session.method == NanoHTTPD.Method.DELETE ->
            deleteExternal(query["volume"], path)
        session.uri == "/api/media/metadata" && session.method == NanoHTTPD.Method.GET ->
            videoMetadata(query["volume"], path)
        session.uri == "/api/media/thumbnail" && session.method == NanoHTTPD.Method.GET ->
            videoThumbnail(query["volume"], path)
        else -> null
    }
}
