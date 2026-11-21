package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.content.SharedPreferences
import android.os.StatFs
import androidx.documentfile.provider.DocumentFile
import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

/**
 * Owns SAF-backed removable-storage listing and mutations.
 * HTTP route dispatch remains in NativeApiServer; response semantics are preserved here.
 */
internal class ExternalStorageOperations(
    private val context: Context,
    private val prefs: SharedPreferences,
    private val storage: ExternalStorageAccess,
    private val parseMultipart: (NanoHTTPD.IHTTPSession) -> Pair<String, java.io.File>?,
    private val parseJsonBody: (NanoHTTPD.IHTTPSession) -> JSONObject?,
    private val isValidName: (String) -> Boolean,
    private val mimeFor: (String) -> String,
    private val formatDate: (Long) -> String,
    private val json: (JSONObject) -> NanoHTTPD.Response,
    private val bad: (String) -> NanoHTTPD.Response,
    private val notFound: (String) -> NanoHTTPD.Response,
    private val error: (NanoHTTPD.Response.Status, String) -> NanoHTTPD.Response,
    private val markMediaIndexDirty: () -> Unit,
    private val mutationLock: Any
) {
    fun listVolumes(): NanoHTTPD.Response {
        val items = JSONArray()
        val ids = linkedSetOf<String>()
        prefs.all.keys.filter { it.startsWith("volume_uri_") }.forEach {
            ids.add(it.removePrefix("volume_uri_"))
        }
        if (prefs.getString("usb1", null) != null) ids.add("usb1")
        if (prefs.getString("usb2", null) != null) ids.add("usb2")
        storage.discoveredRemovableVolumes().forEach { (id, _) -> ids.add(id) }
        ids.forEach { id ->
            val root = storage.root(id)
            val available = root?.exists() == true
            val legacyName = when (id) { "usb1" -> "USB Storage 1"; "usb2" -> "USB Storage 2"; else -> id }
            val item = JSONObject()
                .put("id", id)
                .put("name", prefs.getString("volume_name_$id", null) ?: legacyName)
                .put("available", available)
                .put("writable", available && root?.canWrite() == true)

            if (available && root != null) {
                val capacity = if (root.uri.scheme == "file") {
                    try {
                        val stats = StatFs(root.uri.path ?: return@forEach)
                        externalVolumeCapacity(stats.totalBytes, stats.availableBytes)
                    } catch (_: Exception) { null }
                } else {
                    storage.readVolumeCapacity(root.uri)
                }
                capacity?.let {
                    item.put("total_bytes", it.totalBytes)
                        .put("used_bytes", it.usedBytes)
                        .put("available_bytes", it.availableBytes)
                        .put("usage_percent", it.usagePercent)
                }
            }
            items.put(item)
        }
        return json(JSONObject().put("items", items))
    }

    fun list(volume: String?, relative: String): NanoHTTPD.Response {
        val root = storage.root(volume) ?: return notFound("Storage permission not granted")
        val directory = storage.resolveDocument(root, relative) ?: return notFound("Folder not found")
        if (!directory.isDirectory) return bad("Not a directory")
        val items = JSONArray()
        directory.listFiles().filter { !it.name.orEmpty().startsWith(".") }
            .sortedWith(compareBy<DocumentFile>({ !it.isDirectory }, { it.name.orEmpty().lowercase(Locale.ROOT) }))
            .forEach { item ->
                items.put(JSONObject().put("name", item.name ?: "")
                    .put("type", if (item.isDirectory) "directory" else "file")
                    .put("size", item.length()).put("modified", formatDate(item.lastModified())))
            }
        return json(JSONObject().put("path", relative).put("items", items))
    }

    fun upload(volume: String?, relative: String, session: NanoHTTPD.IHTTPSession): NanoHTTPD.Response {
        val root = storage.root(volume) ?: return notFound("Storage permission not granted")
        val parent = storage.resolveDocument(root, relative) ?: return notFound("Destination folder not found")
        if (!parent.isDirectory) return bad("Destination is not a folder")
        val (name, temp) = parseMultipart(session) ?: return bad("Multipart field 'file' is required")
        if (!isValidName(name)) { temp.delete(); return bad("Invalid filename") }
        val staged = parent.createFile(mimeFor(name), ".pocketlink-upload-${UUID.randomUUID()}.part")
            ?: run { temp.delete(); return error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Could not stage upload") }
        return try {
            context.contentResolver.openOutputStream(staged.uri, "wt")?.use { output ->
                temp.inputStream().use { input -> input.copyTo(output) }
            } ?: return error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Cannot write file")
            synchronized(mutationLock) {
                when {
                    parent.findFile(name) != null ->
                        error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
                    !staged.renameTo(name) ->
                        if (parent.findFile(name) != null) {
                            error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
                        } else {
                            error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Could not finalize uploaded file")
                        }
                    else -> json(JSONObject().put("ok", true).put("name", name))
                        .also { markMediaIndexDirty() }
                }
            }
        } finally {
            temp.delete()
            if (staged.exists()) staged.delete()
        }
    }

    fun mutate(session: NanoHTTPD.IHTTPSession, operation: String): NanoHTTPD.Response {
        val body = parseJsonBody(session) ?: return bad("Invalid JSON body")
        val root = storage.root(body.optString("volume")) ?: return notFound("Storage permission not granted")
        val relative = body.optString("path")
        val name = if (operation == "mkdir") body.optString("name") else body.optString("new_name")
        if (!isValidName(name)) return bad("Invalid name")
        return synchronized(mutationLock) {
            val target: DocumentFile
            if (operation == "mkdir") {
                val parent = storage.resolveDocument(root, relative)
                    ?: return@synchronized notFound("Folder not found")
                if (parent.findFile(name) != null) {
                    return@synchronized error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
                }
                target = parent.createDirectory(name)
                    ?: return@synchronized error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Could not create folder")
            } else {
                target = storage.resolveDocument(root, relative)
                    ?: return@synchronized notFound("Item not found")
                if (target.parentFile?.findFile(name) != null) {
                    return@synchronized error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
                }
                if (!target.renameTo(name)) {
                    return@synchronized if (target.parentFile?.findFile(name) != null) {
                        error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
                    } else {
                        error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Rename failed")
                    }
                }
            }
            json(JSONObject().put("ok", true).put("name", target.name ?: name))
                .also { markMediaIndexDirty() }
        }
    }

    fun delete(volume: String?, relative: String): NanoHTTPD.Response {
        val root = storage.root(volume) ?: return notFound("Storage permission not granted")
        if (relative.isBlank()) return bad("Cannot delete storage root")
        val item = storage.resolveDocument(root, relative) ?: return notFound("Item not found")
        return if (item.delete()) {
            markMediaIndexDirty()
            json(JSONObject().put("ok", true))
        } else error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Delete failed")
    }
}
