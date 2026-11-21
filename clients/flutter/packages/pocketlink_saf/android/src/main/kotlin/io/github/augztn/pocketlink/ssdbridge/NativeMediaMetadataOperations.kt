package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import fi.iki.elonen.NanoHTTPD
import java.io.ByteArrayOutputStream
import java.io.ByteArrayInputStream
import java.io.File
import java.util.Locale
import org.json.JSONObject

/** Owns media metadata and thumbnail extraction for internal and SAF-backed files. */
internal class NativeMediaMetadataOperations(
    private val context: Context,
    private val externalStorage: ExternalStorageAccess,
    private val internalFile: (String) -> File?,
    private val bad: (String) -> NanoHTTPD.Response,
    private val notFound: (String) -> NanoHTTPD.Response,
    private val error: (NanoHTTPD.Response.Status, String) -> NanoHTTPD.Response,
    private val json: (JSONObject) -> NanoHTTPD.Response,
    private val fixedResponse: (String, ByteArray, String) -> NanoHTTPD.Response
) {
    private fun withMediaSource(
        volume: String?,
        relative: String,
        allowAudio: Boolean = false,
        action: (MediaMetadataRetriever) -> NanoHTTPD.Response
    ): NanoHTTPD.Response {
        if (relative.isBlank()) return bad("Media path is required")
        val retriever = MediaMetadataRetriever()
        return try {
            if (volume.isNullOrBlank()) {
                val file = internalFile(relative) ?: return notFound("Media not found")
                val supported = isVideoFile(file.name) || (allowAudio && isAudioFile(file.name))
                if (!file.isFile || !file.canRead() || !supported) return bad("Not a readable media file")
                retriever.setDataSource(file.absolutePath)
            } else {
                val root = externalStorage.root(volume) ?: return notFound("Storage permission not granted")
                val document = externalStorage.resolveDocument(root, relative) ?: return notFound("Media not found")
                val name = document.name.orEmpty()
                val supported = isVideoFile(name) || (allowAudio && isAudioFile(name))
                if (!document.isFile || !supported) return bad("Unsupported media file")
                retriever.setDataSource(context, document.uri)
            }
            action(retriever)
        } catch (_: SecurityException) {
            error(NanoHTTPD.Response.Status.FORBIDDEN, "Storage permission was revoked")
        } catch (_: Exception) {
            notFound("Media metadata is unavailable")
        } finally {
            try { retriever.release() } catch (_: Exception) { }
        }
    }

    fun videoMetadata(volume: String?, relative: String): NanoHTTPD.Response =
        withMediaSource(volume, relative, allowAudio = true) { retriever ->
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            json(JSONObject().put("duration_ms", duration)
                .put("width", if (rotation == 90 || rotation == 270) height else width)
                .put("height", if (rotation == 90 || rotation == 270) width else height))
        }

    fun videoThumbnail(volume: String?, relative: String): NanoHTTPD.Response =
        withMediaSource(volume, relative) { retriever ->
            val frame = retriever.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return@withMediaSource notFound("Video thumbnail unavailable")
            val thumbnail = if (frame.width > 640) {
                Bitmap.createScaledBitmap(
                    frame, 640, (frame.height * 640f / frame.width).toInt().coerceAtLeast(1), true
                )
            } else frame
            val output = ByteArrayOutputStream()
            try {
                if (!thumbnail.compress(Bitmap.CompressFormat.JPEG, 78, output)) {
                    return@withMediaSource error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Could not encode thumbnail")
                }
                fixedResponse("image/jpeg", output.toByteArray(), "private, max-age=86400")
            } finally {
                if (thumbnail !== frame) thumbnail.recycle()
                frame.recycle()
                output.close()
            }
        }

    private fun isVideoFile(name: String): Boolean =
        name.substringAfterLast(".", "").lowercase(Locale.ROOT) in setOf(
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "mpeg", "mpg",
            "3gp", "ts", "m2ts", "mts", "flv", "f4v", "3g2", "m2v", "ogv", "vob", "rmvb"
        )

    private fun isAudioFile(name: String): Boolean =
        name.substringAfterLast(".", "").lowercase(Locale.ROOT) in setOf(
            "mp3", "flac", "m4a", "wav", "ogg", "aac", "opus", "wma", "aiff", "alac", "amr"
        )
}
