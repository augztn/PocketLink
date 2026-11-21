package io.github.augztn.pocketlink.ssdbridge

internal object MediaFileClassifier {
    internal val AUDIO_EXTENSIONS = setOf("mp3", "flac", "m4a", "wav", "ogg", "aac", "opus", "wma")
    internal val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "webm", "mov", "avi", "m4v", "3gp", "ts")
    internal val PHOTO_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "heif", "tif", "tiff", "avif")

    internal val AUDIO_MIME_TYPES = setOf(
        "audio/mpeg", "audio/flac", "audio/x-flac", "audio/mp4", "audio/x-m4a",
        "audio/wav", "audio/x-wav", "audio/ogg", "audio/aac", "audio/opus",
        "audio/x-ms-wma"
    )
    internal val VIDEO_MIME_TYPES = setOf(
        "video/mp4", "video/x-m4v", "video/x-matroska", "video/webm",
        "video/quicktime", "video/x-msvideo", "video/3gpp", "video/mp2t"
    )
    internal val PHOTO_MIME_TYPES = setOf(
        "image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp",
        "image/heic", "image/heif", "image/tiff", "image/avif"
    )

    private val photoExtensions = setOf(
        "jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "heif", "avif",
        "tif", "tiff", "jxl", "dng", "cr2", "nef", "arw", "orf", "rw2"
    )

    private val mimeTypes = mapOf(
        "mp3" to "audio/mpeg", "m4a" to "audio/mp4", "aac" to "audio/aac",
        "flac" to "audio/flac", "ogg" to "audio/ogg", "opus" to "audio/ogg",
        "wav" to "audio/wav", "wma" to "audio/x-ms-wma", "aiff" to "audio/aiff",
        "alac" to "audio/mp4", "amr" to "audio/amr",
        "mp4" to "video/mp4", "m4v" to "video/mp4", "mov" to "video/quicktime",
        "mkv" to "video/x-matroska", "webm" to "video/webm", "avi" to "video/x-msvideo",
        "wmv" to "video/x-ms-wmv", "mpeg" to "video/mpeg", "mpg" to "video/mpeg",
        "h264" to "video/avc", "h265" to "video/hevc", "hevc" to "video/hevc",
        "3gp" to "video/3gpp", "ts" to "video/mp2t", "m2ts" to "video/mp2t",
        "mts" to "video/mp2t", "flv" to "video/x-flv", "ogv" to "video/ogg",
        "jpg" to "image/jpeg", "jpeg" to "image/jpeg", "png" to "image/png",
        "webp" to "image/webp", "gif" to "image/gif", "bmp" to "image/bmp",
        "heic" to "image/heic", "heif" to "image/heif", "avif" to "image/avif",
        "tif" to "image/tiff", "tiff" to "image/tiff", "jxl" to "image/jxl",
        "pdf" to "application/pdf", "doc" to "application/msword",
        "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" to "application/vnd.ms-excel",
        "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt" to "application/vnd.ms-powerpoint",
        "pptx" to "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "odt" to "application/vnd.oasis.opendocument.text",
        "ods" to "application/vnd.oasis.opendocument.spreadsheet",
        "odp" to "application/vnd.oasis.opendocument.presentation",
        "txt" to "text/plain", "md" to "text/markdown", "csv" to "text/csv",
        "html" to "text/html", "htm" to "text/html", "css" to "text/css",
        "xml" to "application/xml", "json" to "application/json",
        "js" to "text/javascript",
        "py" to "text/x-python", "dart" to "text/x-dart", "kt" to "text/x-kotlin",
        "java" to "text/x-java-source", "sh" to "text/x-shellscript",
        "zip" to "application/zip", "7z" to "application/x-7z-compressed",
        "rar" to "application/vnd.rar", "tar" to "application/x-tar",
        "gz" to "application/gzip", "apk" to "application/vnd.android.package-archive",
        "epub" to "application/epub+zip"
    )

    internal fun categoryFor(name: String, mime: String): String? {
        val extension = name.substringAfterLast('.', "").lowercase()
        val normalizedMime = mime.substringBefore(';').trim().lowercase()
        val genericMime = normalizedMime.isEmpty() || normalizedMime == "application/octet-stream"
        return when {
            extension in AUDIO_EXTENSIONS && (genericMime || normalizedMime in AUDIO_MIME_TYPES) -> "music"
            extension in VIDEO_EXTENSIONS && (genericMime || normalizedMime in VIDEO_MIME_TYPES) -> "video"
            extension in photoExtensions -> "photo"
            else -> null
        }
    }

    internal fun mimeForName(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return mimeTypes[extension]
            ?: android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }
}
