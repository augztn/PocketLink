package io.github.augztn.pocketlink.ssdbridge

import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.UUID

/**
 * Owns filesystem operations for PocketLink's internal shared-storage root.
 * HTTP parsing/response construction remain in NativeApiServer.
 */
internal class InternalStorageOperations(
    private val root: () -> File,
    private val resolve: (String) -> File?,
    private val isValidName: (String) -> Boolean,
    private val parseMultipart: (NanoHTTPD.IHTTPSession) -> Pair<String, File>?,
    private val parseJsonBody: (NanoHTTPD.IHTTPSession) -> JSONObject?,
    private val fileJson: (File) -> JSONObject,
    private val fileResponse: (File, NanoHTTPD.IHTTPSession, Boolean) -> NanoHTTPD.Response,
    private val json: (JSONObject) -> NanoHTTPD.Response,
    private val error: (NanoHTTPD.Response.Status, String) -> NanoHTTPD.Response,
    private val markMediaIndexDirty: () -> Unit,
    private val mutationLock: Any
) {
    fun list(relative: String): NanoHTTPD.Response {
        val directory = resolve(relative) ?: return error(NanoHTTPD.Response.Status.NOT_FOUND, "Folder not found")
        if (!directory.isDirectory) return error(NanoHTTPD.Response.Status.BAD_REQUEST, "Not a directory")
        val items = JSONArray()
        (directory.listFiles() ?: emptyArray()).asSequence()
            .filter { !it.name.startsWith(".") }
            .sortedWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase(Locale.ROOT) }))
            .forEach { items.put(fileJson(it)) }
        return json(JSONObject().put("path", relative).put("items", items))
    }

    fun serveFile(
        relative: String,
        session: NanoHTTPD.IHTTPSession,
        inline: Boolean
    ): NanoHTTPD.Response {
        val file = resolve(relative) ?: return error(NanoHTTPD.Response.Status.NOT_FOUND, "File not found")
        if (!file.isFile || !file.canRead()) {
            return error(NanoHTTPD.Response.Status.NOT_FOUND, "File not found")
        }
        return fileResponse(file, session, inline)
    }

    fun upload(relative: String, session: NanoHTTPD.IHTTPSession): NanoHTTPD.Response {
        val (name, temp) = parseMultipart(session)
            ?: return error(NanoHTTPD.Response.Status.BAD_REQUEST, "Multipart field 'file' is required")
        if (!isValidName(name)) {
            temp.delete()
            return error(NanoHTTPD.Response.Status.BAD_REQUEST, "Invalid filename")
        }
        return try {
            synchronized(mutationLock) {
                val parent = resolve(relative)
                    ?: return@synchronized error(NanoHTTPD.Response.Status.NOT_FOUND, "Destination folder not found")
                if (!parent.isDirectory || !parent.canWrite()) {
                    return@synchronized error(NanoHTTPD.Response.Status.BAD_REQUEST, "Destination is not writable")
                }
                val target = File(parent, name)
                val staging = File(parent, ".pocketlink-upload-${UUID.randomUUID()}.part")
                try {
                    if (!temp.renameTo(staging)) temp.copyTo(staging, overwrite = false).also { temp.delete() }
                    when {
                        target.exists() ->
                            error(NanoHTTPD.Response.Status.CONFLICT, "An item with this name already exists")
                        !staging.renameTo(target) ->
                            if (target.exists()) {
                                error(NanoHTTPD.Response.Status.CONFLICT, "An item with this name already exists")
                            } else {
                                error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Could not finalize uploaded file")
                            }
                        else -> json(JSONObject().put("ok", true).put("name", name))
                            .also { markMediaIndexDirty() }
                    }
                } finally {
                    if (staging.exists()) staging.delete()
                }
            }
        } finally {
            temp.delete()
        }
    }

    fun mutate(session: NanoHTTPD.IHTTPSession, operation: String): NanoHTTPD.Response {
        val body = parseJsonBody(session)
            ?: return error(NanoHTTPD.Response.Status.BAD_REQUEST, "Invalid JSON body")
        val relative = body.optString("path")
        val name = if (operation == "mkdir") body.optString("name") else body.optString("new_name")
        if (!isValidName(name)) return error(NanoHTTPD.Response.Status.BAD_REQUEST, "Invalid name")

        return synchronized(mutationLock) {
            if (operation == "mkdir") {
                val parent = resolve(relative)
                    ?: return@synchronized error(NanoHTTPD.Response.Status.NOT_FOUND, "Folder not found")
                if (!parent.isDirectory) {
                    return@synchronized error(NanoHTTPD.Response.Status.BAD_REQUEST, "Not a directory")
                }
                val target = File(parent, name)
                if (target.exists()) {
                    return@synchronized error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
                }
                return@synchronized if (target.mkdir()) {
                    markMediaIndexDirty()
                    json(JSONObject().put("ok", true).put("name", name))
                } else {
                    error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Could not create folder")
                }
            }

            val oldFile = resolve(relative)
                ?: return@synchronized error(NanoHTTPD.Response.Status.NOT_FOUND, "Item not found")
            if (oldFile == root()) {
                return@synchronized error(NanoHTTPD.Response.Status.BAD_REQUEST, "Cannot rename storage root")
            }
            val parent = oldFile.parentFile
                ?: return@synchronized error(NanoHTTPD.Response.Status.BAD_REQUEST, "Invalid parent folder")
            val target = File(parent, name)
            if (target.exists()) {
                return@synchronized error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
            }
            if (oldFile.renameTo(target)) {
                markMediaIndexDirty()
                json(JSONObject().put("ok", true).put("name", name))
            } else if (target.exists()) {
                error(NanoHTTPD.Response.Status.CONFLICT, "Name already exists")
            } else {
                error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Rename failed")
            }
        }
    }

    fun delete(relative: String): NanoHTTPD.Response = synchronized(mutationLock) {
        val file = resolve(relative)
            ?: return@synchronized error(NanoHTTPD.Response.Status.NOT_FOUND, "Item not found")
        if (file == root()) {
            return@synchronized error(NanoHTTPD.Response.Status.BAD_REQUEST, "Cannot delete storage root")
        }
        if (file.isDirectory && file.list()?.isNotEmpty() == true) {
            return@synchronized error(NanoHTTPD.Response.Status.BAD_REQUEST, "Folder is not empty")
        }
        if (file.delete()) {
            markMediaIndexDirty()
            json(JSONObject().put("ok", true))
        } else {
            error(NanoHTTPD.Response.Status.INTERNAL_ERROR, "Delete failed")
        }
    }
}
