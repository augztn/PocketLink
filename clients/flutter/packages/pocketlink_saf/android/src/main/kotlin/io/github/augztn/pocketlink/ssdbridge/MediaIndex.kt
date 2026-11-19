package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal data class IndexedFile(
    val volume: String,
    val path: String,
    val name: String,
    val type: String,
    val size: Long,
    val modified: Long,
    val mime: String,
    val category: String?
)

internal data class IndexStamp(val size: Long, val modified: Long, val category: String? = null)

internal data class SkippedIndexItem(val volume: String, val path: String, val reason: String)

internal class MediaIndexDatabase(context: Context) :
    SQLiteOpenHelper(context, "pocketlink_index.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE files (
                volume TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL,
                type TEXT NOT NULL, size INTEGER NOT NULL, modified INTEGER NOT NULL,
                mime TEXT NOT NULL, scan_id TEXT NOT NULL,
                PRIMARY KEY(volume, path)
            )
        """.trimIndent())
        db.execSQL("""
            CREATE TABLE media (
                volume TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL,
                category TEXT NOT NULL, size INTEGER NOT NULL, modified INTEGER NOT NULL,
                mime TEXT NOT NULL, scan_id TEXT NOT NULL,
                PRIMARY KEY(volume, path)
            )
        """.trimIndent())
        db.execSQL("CREATE INDEX files_name_idx ON files(name COLLATE NOCASE)")
        db.execSQL("CREATE INDEX files_modified_idx ON files(modified DESC)")
        db.execSQL("CREATE INDEX media_category_name_idx ON media(category, name COLLATE NOCASE)")
        db.execSQL("CREATE INDEX media_modified_idx ON media(category, modified DESC)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun upsertFiles(batch: List<IndexedFile>, scanId: String) {
        if (batch.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            val statement = db.compileStatement("""
                INSERT OR REPLACE INTO files(volume,path,name,type,size,modified,mime,scan_id)
                VALUES(?,?,?,?,?,?,?,?)
            """.trimIndent())
            try {
                batch.forEach { item ->
                    statement.clearBindings()
                    statement.bindString(1, item.volume)
                    statement.bindString(2, item.path)
                    statement.bindString(3, item.name)
                    statement.bindString(4, item.type)
                    statement.bindLong(5, item.size)
                    statement.bindLong(6, item.modified)
                    statement.bindString(7, item.mime)
                    statement.bindString(8, scanId)
                    statement.executeInsert()
                }
            } finally { statement.close() }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    fun upsertMedia(batch: List<IndexedFile>, scanId: String) {
        val mediaItems = batch.filter { it.category != null && it.type == "file" }
        if (mediaItems.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            val statement = db.compileStatement("""
                INSERT OR REPLACE INTO media(volume,path,name,category,size,modified,mime,scan_id)
                VALUES(?,?,?,?,?,?,?,?)
            """.trimIndent())
            try {
                mediaItems.forEach { item ->
                    statement.clearBindings()
                    statement.bindString(1, item.volume)
                    statement.bindString(2, item.path)
                    statement.bindString(3, item.name)
                    statement.bindString(4, item.category!!)
                    statement.bindLong(5, item.size)
                    statement.bindLong(6, item.modified)
                    statement.bindString(7, item.mime)
                    statement.bindString(8, scanId)
                    statement.executeInsert()
                }
            } finally { statement.close() }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    fun finishFilesSource(volume: String, scanId: String) {
        writableDatabase.delete("files", "volume=? AND scan_id<>?", arrayOf(volume, scanId))
    }

    fun finishMediaSource(volume: String, scanId: String) {
        writableDatabase.delete("media", "volume=? AND scan_id<>?", arrayOf(volume, scanId))
    }

    fun fileSnapshot(volume: String): Map<String, IndexStamp> {
        val result = mutableMapOf<String, IndexStamp>()
        readableDatabase.query("files", arrayOf("path", "size", "modified"),
            "volume=?", arrayOf(volume), null, null, null).use { cursor ->
            while (cursor.moveToNext()) result[cursor.getString(0)] =
                IndexStamp(cursor.getLong(1), cursor.getLong(2))
        }
        return result
    }

    fun mediaSnapshot(volume: String): Map<String, IndexStamp> {
        val result = mutableMapOf<String, IndexStamp>()
        readableDatabase.query("media", arrayOf("path", "size", "modified", "category"),
            "volume=?", arrayOf(volume), null, null, null).use { cursor ->
            while (cursor.moveToNext()) result[cursor.getString(0)] =
                IndexStamp(cursor.getLong(1), cursor.getLong(2), cursor.getString(3))
        }
        return result
    }

    fun markFilesSeen(volume: String, paths: List<String>, scanId: String) =
        markSeen("files", volume, paths, scanId)

    fun markMediaSeen(volume: String, paths: List<String>, scanId: String) =
        markSeen("media", volume, paths, scanId)

    private fun markSeen(table: String, volume: String, paths: List<String>, scanId: String) {
        if (paths.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            val statement = db.compileStatement("UPDATE $table SET scan_id=? WHERE volume=? AND path=?")
            try {
                paths.forEach { path ->
                    statement.clearBindings()
                    statement.bindString(1, scanId)
                    statement.bindString(2, volume)
                    statement.bindString(3, path)
                    statement.executeUpdateDelete()
                }
            } finally { statement.close() }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    fun queryMedia(category: String, query: String, limit: Int, offset: Int): List<IndexedFile> {
        val rows = mutableListOf<IndexedFile>()
        val where = if (query.isBlank()) "category=?" else "category=? AND (name LIKE ? ESCAPE '\\' OR path LIKE ? ESCAPE '\\')"
        val args = if (query.isBlank()) arrayOf(category) else {
            val escaped = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            arrayOf(category, escaped, escaped)
        }
        readableDatabase.query(
            "media", arrayOf("volume","path","name","category","size","modified","mime"),
            where, args, null, null, "name COLLATE NOCASE ASC", "$offset,$limit"
        ).use { cursor ->
            while (cursor.moveToNext()) rows += IndexedFile(
                cursor.getString(0), cursor.getString(1), cursor.getString(2), "file",
                cursor.getLong(4), cursor.getLong(5), cursor.getString(6), cursor.getString(3)
            )
        }
        return rows
    }

    fun searchFiles(query: String, limit: Int, offset: Int): List<IndexedFile> {
        val rows = mutableListOf<IndexedFile>()
        val where = if (query.isBlank()) null else "name LIKE ? ESCAPE '\\' OR path LIKE ? ESCAPE '\\'"
        val escaped = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        readableDatabase.query(
            "files", arrayOf("volume","path","name","type","size","modified","mime"),
            where, if (where == null) null else arrayOf(escaped, escaped),
            null, null, "name COLLATE NOCASE ASC", "$offset,$limit"
        ).use { cursor ->
            while (cursor.moveToNext()) rows += IndexedFile(
                cursor.getString(0), cursor.getString(1), cursor.getString(2), cursor.getString(3),
                cursor.getLong(4), cursor.getLong(5), cursor.getString(6), null
            )
        }
        return rows
    }

    fun counts(): Map<String, Int> {
        val db = readableDatabase
        fun count(table: String): Int = db.rawQuery("SELECT COUNT(*) FROM $table", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        fun countCategory(category: String): Int =
            db.rawQuery("SELECT COUNT(*) FROM media WHERE category=?", arrayOf(category)).use {
                if (it.moveToFirst()) it.getInt(0) else 0
            }
        fun countType(type: String): Int =
            db.rawQuery("SELECT COUNT(*) FROM files WHERE type=?", arrayOf(type)).use {
                if (it.moveToFirst()) it.getInt(0) else 0
            }
        return mapOf(
            "files" to count("files"),
            "directories" to countType("directory"),
            "regular_files" to countType("file"),
            "media" to count("media"),
            "photo" to countCategory("photo"),
            "video" to countCategory("video"),
            "music" to countCategory("music")
        )
    }
}

internal class MediaIndexScanner(
    context: Context,
    private val internalRoot: () -> File,
    private val externalRoots: () -> List<Pair<String, DocumentFile>>
) {
    private val database = MediaIndexDatabase(context.applicationContext)
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PocketLink-MediaIndex").apply { isDaemon = true }
    }
    private val running = AtomicBoolean(false)
    private val dirty = AtomicBoolean(false)
    @Volatile private var started = false
    @Volatile private var scanned = 0
    @Volatile private var scannedDirectories = 0
    @Volatile private var unchanged = 0
    @Volatile private var skipped = 0
    @Volatile private var state = "idle"
    @Volatile private var lastError: String? = null
    @Volatile private var lastCompletedAt: Long = 0L
    @Volatile private var lastScanStartedAt: Long = 0L
    @Volatile private var currentSource: String? = null
    @Volatile private var currentPath: String? = null
    private val skippedItems = mutableListOf<SkippedIndexItem>()

    private fun recordSkipped(volume: String, path: String, reason: String) {
        synchronized(skippedItems) {
            if (skippedItems.size < MAX_REPORTED_SKIPPED_ITEMS) {
                skippedItems += SkippedIndexItem(volume, path, reason)
            }
        }
    }

    fun markDirty() {
        dirty.set(true)
    }

    fun ensureStarted() {
        val now = System.currentTimeMillis()
        if (!started) {
            requestScan(force = false)
        } else if (!running.get() &&
            (dirty.get() || now - (lastCompletedAt.takeIf { it > 0L } ?: lastScanStartedAt) >= RESCAN_INTERVAL_MS)) {
            // Discover changes made by PocketLink immediately, and external
            // changes periodically. Unchanged rows are not rewritten.
            requestScan(force = true)
        }
    }

    @Synchronized
    fun requestScan(force: Boolean) {
        if (running.get()) {
            // Coalesce refreshes and mutations into one follow-up pass.
            if (force) dirty.set(true)
            return
        }
        if (started && !force && state == "complete") return
        started = true
        lastScanStartedAt = System.currentTimeMillis()
        dirty.set(false)
        running.set(true)
        state = "scanning"
        scanned = 0
        scannedDirectories = 0
        unchanged = 0
        skipped = 0
        currentSource = null
        currentPath = null
        synchronized(skippedItems) { skippedItems.clear() }
        lastError = null
        executor.execute {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            try {
                val sources = mutableListOf<Pair<String, Any>>()
                sources += "internal" to internalRoot()
                externalRoots().forEach { (id, root) -> sources += id to root }
                sources.forEach { (id, root) ->
                    currentSource = id
                    try {
                        scanSource(id, root)
                    } catch (error: Exception) {
                        skipped++
                        recordSkipped(id, "", error.message ?: "Storage source could not be indexed")
                        lastError = error.message ?: "One storage source could not be indexed"
                    } finally {
                        currentSource = null
                        currentPath = null
                    }
                }
                if (lastError == null && skipped > 0) lastError = "Some files or folders could not be indexed."
                state = if (lastError == null && skipped == 0) "complete" else "partial"
                lastCompletedAt = System.currentTimeMillis()
            } catch (error: Exception) {
                state = "failed"
                lastError = error.message ?: "Index scan failed"
            } finally {
                val scanAgain = synchronized(this) {
                    running.set(false)
                    dirty.getAndSet(false)
                }
                if (scanAgain) requestScan(force = true)
            }
        }
    }

    private fun scanSource(volume: String, root: Any) {
        val scanId = UUID.randomUUID().toString()
        val fileSnapshot = database.fileSnapshot(volume)
        val mediaSnapshot = database.mediaSnapshot(volume)
        val batch = ArrayList<IndexedFile>(200)
        val unchangedFiles = ArrayList<String>(200)
        val unchangedMedia = ArrayList<String>(200)
        var complete = true
        var filesHealthy = true
        var mediaHealthy = true
        fun flush() {
            val snapshot = batch.toList()
            if (snapshot.isNotEmpty()) {
                try { database.upsertFiles(snapshot, scanId) } catch (error: Exception) {
                    filesHealthy = false
                    skipped++
                    recordSkipped(volume, "", error.message ?: "File index update failed")
                    lastError = error.message ?: "File index update failed"
                }
                try { database.upsertMedia(snapshot, scanId) } catch (error: Exception) {
                    mediaHealthy = false
                    skipped++
                    recordSkipped(volume, "", error.message ?: "Media index update failed")
                    lastError = error.message ?: "Media index update failed"
                }
            }
            try { database.markFilesSeen(volume, unchangedFiles.toList(), scanId) } catch (error: Exception) {
                filesHealthy = false
                skipped++
                recordSkipped(volume, "", error.message ?: "File index update failed")
                lastError = error.message ?: "File index update failed"
            }
            try { database.markMediaSeen(volume, unchangedMedia.toList(), scanId) } catch (error: Exception) {
                mediaHealthy = false
                skipped++
                recordSkipped(volume, "", error.message ?: "Media index update failed")
                lastError = error.message ?: "Media index update failed"
            }
            batch.clear()
            unchangedFiles.clear()
            unchangedMedia.clear()
        }
        fun add(path: String, name: String, directory: Boolean, size: Long, modified: Long, mime: String) {
            val safeSize = size.coerceAtLeast(0L)
            val safeModified = modified.coerceAtLeast(0L)
            val category = if (directory) null else categoryFor(name)
            val previousFile = fileSnapshot[path]
            val previousMedia = mediaSnapshot[path]
            // Some SAF providers always report modified=0. In that case use
            // size + category as the best available stable fingerprint.
            val fileUnchanged = previousFile != null &&
                previousFile.size == safeSize &&
                (if (safeModified <= 0L) previousFile.modified <= 0L
                else previousFile.modified == safeModified)
            val mediaUnchanged = when {
                category == null -> previousMedia == null
                previousMedia == null -> false
                previousMedia.size != safeSize || previousMedia.category != category -> false
                safeModified <= 0L -> previousMedia.modified <= 0L
                else -> previousMedia.modified == safeModified
            }
            scanned++
            if (fileUnchanged && mediaUnchanged) {
                unchanged++
                unchangedFiles += path
                if (category != null) unchangedMedia += path
            } else {
                batch += IndexedFile(volume, path, name, if (directory) "directory" else "file",
                    safeSize, safeModified, mime, category)
            }
            if (batch.size >= 200 || unchangedFiles.size >= 200) flush()
        }

        when (root) {
            is File -> {
                val base = root.canonicalFile
                val stack = ArrayDeque<Pair<File, Int>>()
                stack.add(base to 0)
                while (stack.isNotEmpty()) {
                    val (directory, depth) = stack.removeLast()
                    currentPath = runCatching {
                        if (directory == base) "" else directory.canonicalFile.relativeTo(base).invariantSeparatorsPath
                    }.getOrDefault("")
                    scannedDirectories++
                    val children = try { directory.listFiles() } catch (_: Exception) { null }
                    if (children == null) {
                        complete = false
                        skipped++
                        val inaccessiblePath = runCatching { directory.canonicalFile.relativeTo(base).invariantSeparatorsPath }.getOrDefault("")
                        recordSkipped(volume, inaccessiblePath, "Folder could not be read")
                        continue
                    }
                    children.forEach { child ->
                        if (child.name.startsWith(".")) return@forEach
                        val canonical = try { child.canonicalFile } catch (_: Exception) { null }
                        if (canonical == null || !(canonical.path == base.path ||
                                canonical.path.startsWith(base.path + File.separator))) {
                            complete = false
                            skipped++
                            recordSkipped(volume, child.name, "Path could not be safely resolved")
                            return@forEach
                        }
                        val relative = canonical.relativeTo(base).invariantSeparatorsPath
                        add(relative, child.name, child.isDirectory, if (child.isFile) child.length() else 0L,
                            child.lastModified(), mimeForName(child.name))
                        if (child.isDirectory) {
                            if (depth < MAX_DEPTH) stack.add(child to depth + 1)
                            else { complete = false; skipped++; recordSkipped(volume, relative, "Maximum folder depth reached") }
                        }
                    }
                }
            }
            is DocumentFile -> {
                val stack = ArrayDeque<Pair<Pair<DocumentFile, String>, Int>>()
                stack.add((root to "") to 0)
                while (stack.isNotEmpty()) {
                    val (entry, depth) = stack.removeLast()
                    val (directory, parentPath) = entry
                    currentPath = parentPath
                    scannedDirectories++
                    val children = try { directory.listFiles() } catch (_: Exception) { null }
                    if (children == null) {
                        complete = false
                        skipped++
                        recordSkipped(volume, parentPath, "Folder could not be read")
                        continue
                    }
                    children.forEach { child ->
                        val name = child.name ?: run {
                            complete = false
                            skipped++
                            recordSkipped(volume, parentPath, "Storage provider returned an item without a name")
                            return@forEach
                        }
                        if (name.startsWith(".")) return@forEach
                        val relative = if (parentPath.isEmpty()) name else "$parentPath/$name"
                        add(relative, name, child.isDirectory, if (child.isFile) child.length() else 0L,
                            child.lastModified(), child.type ?: mimeForName(name))
                        if (child.isDirectory) {
                            if (depth < MAX_DEPTH) stack.add((child to relative) to depth + 1)
                            else { complete = false; skipped++; recordSkipped(volume, relative, "Maximum folder depth reached") }
                        }
                    }
                }
            }
        }
        flush()
        // Each index is committed and pruned independently. A media-index
        // failure must not invalidate the general file index, or vice versa.
        if (complete && filesHealthy) database.finishFilesSource(volume, scanId)
        if (complete && mediaHealthy) database.finishMediaSource(volume, scanId)
    }

    fun status(): org.json.JSONObject {
        val counts = database.counts()
        return org.json.JSONObject()
            .put("state", state)
            .put("scanned", scanned)
            .put("scanned_directories", scannedDirectories)
            .put("unchanged_count", unchanged)
            .put("indexed_count", (scanned - unchanged).coerceAtLeast(0))
            .put("skipped", skipped)
            .put("last_completed_at", lastCompletedAt)
            .put("last_scan_started_at", lastScanStartedAt)
            .put("elapsed_ms", if (state == "scanning") System.currentTimeMillis() - lastScanStartedAt else (lastCompletedAt - lastScanStartedAt).coerceAtLeast(0L))
            .put("current_source", currentSource)
            .put("current_path", currentPath)
            .put("last_error", lastError)
            .put("skipped_items", org.json.JSONArray().also { items ->
                synchronized(skippedItems) {
                    skippedItems.forEach { item ->
                        items.put(org.json.JSONObject()
                            .put("volume", item.volume)
                            .put("path", item.path)
                            .put("reason", item.reason))
                    }
                }
            })
            .put("file_count", counts["files"] ?: 0)
            .put("directory_count", counts["directories"] ?: 0)
            .put("regular_file_count", counts["regular_files"] ?: 0)
            .put("media_count", counts["media"] ?: 0)
            .put("photo_count", counts["photo"] ?: 0)
            .put("video_count", counts["video"] ?: 0)
            .put("music_count", counts["music"] ?: 0)
    }

    fun media(category: String, query: String, limit: Int, offset: Int) =
        database.queryMedia(category, query, limit, offset)

    fun files(query: String, limit: Int, offset: Int) =
        database.searchFiles(query, limit, offset)

    /** Release scanner resources after a completed scan (primarily for tests). */
    fun close() {
        executor.shutdown()
        try {
            executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        database.close()
    }

    companion object {
        private const val RESCAN_INTERVAL_MS = 10 * 60 * 1000L
        private const val MAX_DEPTH = 64
        private const val MAX_REPORTED_SKIPPED_ITEMS = 100
        private val AUDIO = setOf(
            "mp3","m4a","aac","wav","flac","ogg","opus","wma","aiff","alac",
            "amr","ape","wv","dsf","dff","mid","midi","mka"
        )
        private val VIDEO = setOf(
            "mp4","m4v","mov","mkv","webm","avi","wmv","mpeg","mpg","3gp",
            "ts","m2ts","mts","flv","f4v","3g2","m2v","ogv","vob","rmvb",
            "h264","h265","hevc"
        )
        private val PHOTO = setOf(
            "jpg","jpeg","png","webp","gif","bmp","heic","heif","avif",
            "tif","tiff","jxl","dng","cr2","nef","arw","orf","rw2"
        )

        private fun categoryFor(name: String): String? = when (name.substringAfterLast('.', "").lowercase()) {
            in AUDIO -> "music"
            in VIDEO -> "video"
            in PHOTO -> "photo"
            else -> null
        }

        private val MIME_TYPES = mapOf(
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
                "js" to "text/javascript", "ts" to "text/typescript",
                "py" to "text/x-python", "dart" to "text/x-dart", "kt" to "text/x-kotlin",
                "java" to "text/x-java-source", "sh" to "text/x-shellscript",
                "zip" to "application/zip", "7z" to "application/x-7z-compressed",
                "rar" to "application/vnd.rar", "tar" to "application/x-tar",
                "gz" to "application/gzip", "apk" to "application/vnd.android.package-archive",
                "epub" to "application/epub+zip"
            )

        private fun mimeForName(name: String): String {
            val extension = name.substringAfterLast('.', "").lowercase()
            return MIME_TYPES[extension]
                ?: android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
        }
    }
}
