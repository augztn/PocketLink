package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.net.Uri
import fi.iki.elonen.NanoHTTPD
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FilterInputStream

/**
 * Owns byte-range and streaming HTTP responses for internal and SAF-backed files.
 * Route dispatch and JSON error formatting remain in NativeApiServer.
 */
internal class NativeFileResponseOperations(
    private val context: Context,
    private val externalStorage: ExternalStorageAccess,
    private val error: (NanoHTTPD.Response.Status, String) -> NanoHTTPD.Response,
    private val notFound: (String) -> NanoHTTPD.Response,
    private val bad: (String) -> NanoHTTPD.Response
) {
    fun serveInternalFile(
        file: File,
        session: NanoHTTPD.IHTTPSession,
        inline: Boolean
    ): NanoHTTPD.Response {
        val length = file.length()
        val mime = mimeFor(file.name)
        val range = session.headers["range"]
        val response: NanoHTTPD.Response
        if (range.isNullOrBlank()) {
            response = NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK,
                mime,
                BufferedInputStream(FileInputStream(file), STREAM_BUFFER_SIZE),
                length
            )
        } else {
            val bounds = parseByteRange(range, length)
                ?: return error(NanoHTTPD.Response.Status.RANGE_NOT_SATISFIABLE, "Invalid byte range")
                    .apply { addHeader("Content-Range", "bytes */$length") }
            val (start, end) = bounds
            val input = FileInputStream(file)
            try {
                input.channel.position(start)
            } catch (_: Exception) {
                input.close()
                return error(NanoHTTPD.Response.Status.RANGE_NOT_SATISFIABLE, "Could not seek to byte range")
            }
            response = NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.PARTIAL_CONTENT,
                mime,
                BufferedInputStream(input, STREAM_BUFFER_SIZE),
                end - start + 1
            ).apply { addHeader("Content-Range", "bytes $start-$end/$length") }
        }
        response.addHeader("Accept-Ranges", "bytes")
        response.addHeader("Cache-Control", "no-transform")
        response.addHeader(
            "Content-Disposition",
            "${if (inline) "inline" else "attachment"}; filename*=UTF-8''${java.net.URLEncoder.encode(file.name, "UTF-8").replace("+", "%20")}"
        )
        return response
    }

    fun serveExternalFile(
        volume: String?,
        relative: String,
        session: NanoHTTPD.IHTTPSession
    ): NanoHTTPD.Response {
        val root = externalStorage.root(volume) ?: return notFound("Storage permission not granted")
        val item = externalStorage.resolveDocument(root, relative) ?: return notFound("File not found")
        if (!item.isFile) return bad("Not a file")
        val length = item.length()
        val mime = item.type?.takeIf { it.isNotBlank() } ?: mimeFor(item.name.orEmpty())
        val range = session.headers["range"]
        val response = if (range.isNullOrBlank()) {
            val input = context.contentResolver.openInputStream(item.uri)
                ?: return notFound("Cannot open file")
            val buffered = BufferedInputStream(input, STREAM_BUFFER_SIZE)
            if (length > 0L) {
                NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.OK, mime, buffered, length)
            } else {
                NanoHTTPD.newChunkedResponse(NanoHTTPD.Response.Status.OK, mime, buffered)
            }
        } else {
            if (length <= 0L) {
                return error(
                    NanoHTTPD.Response.Status.RANGE_NOT_SATISFIABLE,
                    "Byte ranges are unavailable for this storage provider"
                )
            }
            val bounds = parseByteRange(range, length)
                ?: return error(NanoHTTPD.Response.Status.RANGE_NOT_SATISFIABLE, "Invalid byte range")
                    .apply { addHeader("Content-Range", "bytes */$length") }
            val (start, end) = bounds
            val input = openExternalRangeStream(item.uri, start)
                ?: return error(
                    NanoHTTPD.Response.Status.RANGE_NOT_SATISFIABLE,
                    "Could not seek to byte range"
                )
            NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.PARTIAL_CONTENT,
                mime,
                input,
                end - start + 1
            ).apply { addHeader("Content-Range", "bytes $start-$end/$length") }
        }
        if (length > 0L) response.addHeader("Accept-Ranges", "bytes")
        response.addHeader("Cache-Control", "no-transform")
        return response
    }

    /**
     * Prefer a seekable descriptor for SAF range requests. Some providers expose
     * non-seekable pipes, so retain a streaming skip fallback for compatibility.
     */
    private fun openExternalRangeStream(uri: Uri, offset: Long): BufferedInputStream? {
        val descriptor = try {
            context.contentResolver.openFileDescriptor(uri, "r")
        } catch (_: Exception) {
            null
        }
        if (descriptor != null) {
            val fileInput = FileInputStream(descriptor.fileDescriptor)
            try {
                fileInput.channel.position(offset)
                val owned = object : FilterInputStream(fileInput) {
                    override fun close() {
                        try { super.close() } finally { descriptor.close() }
                    }
                }
                return BufferedInputStream(owned, STREAM_BUFFER_SIZE)
            } catch (_: Exception) {
                try { fileInput.close() } catch (_: Exception) { }
                try { descriptor.close() } catch (_: Exception) { }
            }
        }

        val input = context.contentResolver.openInputStream(uri) ?: return null
        var skipped = 0L
        val discard = ByteArray(STREAM_BUFFER_SIZE)
        while (skipped < offset) {
            val remaining = offset - skipped
            val count = try {
                val advanced = input.skip(remaining)
                if (advanced > 0L) advanced
                else input.read(discard, 0, minOf(discard.size.toLong(), remaining).toInt()).toLong()
            } catch (_: Exception) {
                -1L
            }
            if (count <= 0L) {
                input.close()
                return null
            }
            skipped += count
        }
        return BufferedInputStream(input, STREAM_BUFFER_SIZE)
    }

    private fun mimeFor(name: String): String =
        when (name.substringAfterLast('.', "").lowercase(java.util.Locale.ROOT)) {
            "jpg", "jpeg" -> "image/jpeg"; "png" -> "image/png"; "gif" -> "image/gif"; "webp" -> "image/webp"
            "mp3" -> "audio/mpeg"; "m4a" -> "audio/mp4"; "mp4" -> "video/mp4"; "aac" -> "audio/aac"
            "flac" -> "audio/flac"; "ogg", "opus" -> "audio/ogg"; "wav" -> "audio/wav"
            "mkv" -> "video/x-matroska"; "pdf" -> "application/pdf"; "txt" -> "text/plain"
            else -> "application/octet-stream"
        }

    companion object {
        private const val STREAM_BUFFER_SIZE = 64 * 1024
    }
}

internal fun parseByteRange(value: String, length: Long): Pair<Long, Long>? {
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
