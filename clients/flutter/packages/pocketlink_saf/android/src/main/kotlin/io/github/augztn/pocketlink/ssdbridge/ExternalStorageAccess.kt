package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import java.io.File

/**
 * Owns Android removable-volume discovery and SAF document-tree resolution.
 * HTTP response formatting and file mutations remain in NativeApiServer.
 */
internal class ExternalStorageAccess(
    private val context: Context,
    private val prefs: SharedPreferences,
    private val isValidName: (String) -> Boolean
) {
    fun root(volume: String?): DocumentFile? {
        val id = volume?.takeIf {
            it == "usb1" || it == "usb2" ||
                Regex("usb-(?:[a-f0-9]{16}|manual-[a-f0-9]{16})").matches(it)
        } ?: return null
        val raw = prefs.getString("volume_uri_$id", null)
            ?: prefs.getString(id, null)
        if (raw != null) {
            DocumentFile.fromTreeUri(context, Uri.parse(raw))
                ?.takeIf { it.exists() && it.canRead() }
                ?.let { return it }
        }

        // StorageManager exposes mounted removable-volume paths to the Android
        // app process. Termux cannot inherit this app's all-files permission.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            !Environment.isExternalStorageManager()
        ) return null
        val volumeInfo = discoveredRemovableVolumes().firstOrNull { it.first == id } ?: return null
        val directory = volumeInfo.second.directory ?: return null
        if (!directory.isDirectory || !directory.canRead()) return null
        return DocumentFile.fromFile(directory)
    }

    fun discoveredRemovableVolumes(): List<Pair<String, StorageVolume>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return emptyList()
        val manager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: return emptyList()
        return manager.storageVolumes.mapNotNull { volume ->
            if (!volume.isRemovable || volume.state !in setOf(
                    Environment.MEDIA_MOUNTED,
                    Environment.MEDIA_MOUNTED_READ_ONLY
                )
            ) return@mapNotNull null
            val directory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) volume.directory else null
            val identity = externalVolumeIdentity(
                volume.uuid,
                directory?.absolutePath,
                volume.getDescription(context).toString()
            )
            externalVolumeKey(identity) to volume
        }
    }

    fun resolveDocument(root: DocumentFile, relative: String): DocumentFile? {
        var current = root
        if (relative.isBlank()) return current
        for (part in relative.split('/')) {
            if (!isValidName(part)) return null
            current = current.findFile(part) ?: return null
        }
        return current
    }

    /**
     * Capacity is intentionally unavailable for unsupported SAF providers or
     * Android versions without a public removable-volume directory API.
     */
    fun readVolumeCapacity(treeUri: Uri): ExternalVolumeCapacity? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        if (treeUri.authority != "com.android.externalstorage.documents") return null

        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val volumeId = externalStorageVolumeId(documentId) ?: return null
            val storageManager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
                ?: return null
            val storageVolume = storageManager.storageVolumes.firstOrNull { volume ->
                volume.isRemovable &&
                    volume.uuid?.equals(volumeId, ignoreCase = true) == true &&
                    volume.state in setOf(
                        Environment.MEDIA_MOUNTED,
                        Environment.MEDIA_MOUNTED_READ_ONLY
                    )
            } ?: return null
            val directory = storageVolume.directory ?: return null
            if (!directory.isDirectory) return null

            val stats = StatFs(directory.absolutePath)
            externalVolumeCapacity(stats.totalBytes, stats.availableBytes)
        } catch (_: Exception) {
            // Capacity is optional; provider/stat failures must not break discovery.
            null
        }
    }
}
