package io.github.augztn.pocketlink.ssdbridge

import android.os.Build
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Owns shared-storage filename validation, file metadata JSON, and UTC date formatting. */
internal class NativeApiFileMetadata {
    fun fileJson(file: File): JSONObject {
        val value = JSONObject()
            .put("name", file.name)
            .put("type", if (file.isDirectory) "directory" else "file")
            .put("size", if (file.isFile) file.length() else 0L)
            .put("modified", formatDate(file.lastModified()))

        // Filesystem birth time is not available on every Android filesystem.
        // Only publish it when the provider supplies a valid value.
        if (file.isFile && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val created = java.nio.file.Files.readAttributes(
                    file.toPath(),
                    java.nio.file.attribute.BasicFileAttributes::class.java
                ).creationTime().toMillis()
                if (created > 0L) value.put("created", formatDate(created))
            } catch (_: Exception) {
                // Some Android/FUSE filesystems do not expose birth time.
            }
        }
        return value
    }

    fun isValidName(value: String): Boolean =
        value.isNotBlank() && value != "." && value != ".." &&
            !value.startsWith(".") && !value.contains('/') && !value.contains('\\') &&
            !value.any { it.code < 32 }

    fun formatDate(timestamp: Long): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date(timestamp))
    }
}
