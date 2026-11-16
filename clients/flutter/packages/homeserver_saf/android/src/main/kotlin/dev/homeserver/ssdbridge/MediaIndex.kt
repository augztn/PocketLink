package dev.homeserver.ssdbridge

import android.content.ContentValues
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

    fun upsert(batch: List<IndexedFile>, scanId: String) {
        if (batch.isEmpty()) return
        writableDatabase.beginTransaction()
        try {
            val db = writableDatabase
            val fileStatement = db.compileStatement("""
                INSERT OR REPLACE INTO files(volume,path,name,type,size,modified,mime,scan_id)
                VALUES(?,?,?,?,?,?,?,?)
            """.trimIndent())
            val mediaStatement = db.compileStatement("""
                INSERT OR REPLACE INTO media(volume,path,name,category,size,modified,mime,scan_id)
                VALUES(?,?,?,?,?,?,?,?)
            """.trimIndent())
            try {
                batch.forEach { item ->
                    fileStatement.clearBindings()
                    fileStatement.bindString(1, item.volume)
                    fileStatement.bindString(2, item.path)
                    fileStatement.bindString(3, item.name)
                    fileStatement.bindString(4, item.type)
                    fileStatement.bindLong(5, item.size)
                    fileStatement.bindLong(6, item.modified)
                    fileStatement.bindString(7, item.mime)
                    fileStatement.bindString(8, scanId)
                    fileStatement.executeInsert()

                    if (item.category != null && item.type == "file") {
                        mediaStatement.clearBindings()
                        mediaStatement.bindString(1, item.volume)
                        mediaStatement.bindString(2, item.path)
                        mediaStatement.bindString(3, item.name)
                        mediaStatement.bindString(4, item.category)
                        mediaStatement.bindLong(5, item.size)
                        mediaStatement.bindLong(6, item.modified)
                        mediaStatement.bindString(7, item.mime)
                        mediaStatement.bindString(8, scanId)
                        mediaStatement.executeInsert()
                    }
                }
            } finally {
                fileStatement.close()
                mediaStatement.close()
            }
            db.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
    }

    fun finishSource(volume: String, scanId: String) {
        writableDatabase.beginTransaction()
        try {
            writableDatabase.delete("files", "volume=? AND scan_id<>?", arrayOf(volume, scanId))
            writableDatabase.delete("media", "volume=? AND scan_id<>?", arrayOf(volume, scanId))
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
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
        return mapOf("files" to count("files"), "media" to count("media"))
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
    @Volatile private var started = false
    @Volatile private var scanned = 0
    @Volatile private var skipped = 0
    @Volatile private var state = "idle"
    @Volatile private var lastError: String? = null
    @Volatile private var lastCompletedAt: Long = 0L

    fun ensureStarted() {
        if (!started) requestScan(force = false)
    }

    @Synchronized
    fun requestScan(force: Boolean) {
        if (running.get()) return
        if (started && !force && state == "complete") return
        started = true
        running.set(true)
        state = "scanning"
        scanned = 0
        skipped = 0
        lastError = null
        executor.execute {
            try {
                val sources = mutableListOf<Pair<String, Any>>()
                sources += "internal" to internalRoot()
                externalRoots().forEach { (id, root) -> sources += id to root }
                sources.forEach { (id, root) ->
                    try {
                        scanSource(id, root)
                    } catch (error: Exception) {
                        skipped++
                        lastError = error.message ?: "One storage source could not be indexed"
                    }
                }
                state = if (lastError == null) "complete" else "partial"
                lastCompletedAt = System.currentTimeMillis()
            } catch (error: Exception) {
                state = "failed"
                lastError = error.message ?: "Index scan failed"
            } finally {
                running.set(false)
            }
        }
    }

    private fun scanSource(volume: String, root: Any) {
        val scanId = UUID.randomUUID().toString()
        val batch = ArrayList<IndexedFile>(200)
        var complete = true
        fun flush() {
            if (batch.isNotEmpty()) {
                database.upsert(batch.toList(), scanId)
                batch.clear()
            }
        }
        fun add(path: String, name: String, directory: Boolean, size: Long, modified: Long, mime: String) {
            val category = if (directory) null else categoryFor(name)
            batch += IndexedFile(volume, path, name, if (directory) "directory" else "file",
                size.coerceAtLeast(0L), modified.coerceAtLeast(0L), mime, category)
            scanned++
            if (batch.size >= 200) flush()
        }

        when (root) {
            is File -> {
                val base = root.canonicalFile
                val stack = ArrayDeque<Pair<File, Int>>()
                stack.add(base to 0)
                while (stack.isNotEmpty()) {
                    val (directory, depth) = stack.removeLast()
                    val children = try { directory.listFiles() } catch (_: Exception) { null }
                    if (children == null) {
                        complete = false
                        skipped++
                        continue
                    }
                    children.forEach { child ->
                        if (child.name.startsWith(".")) return@forEach
                        val canonical = try { child.canonicalFile } catch (_: Exception) { null }
                        if (canonical == null || !(canonical.path == base.path ||
                                canonical.path.startsWith(base.path + File.separator))) {
                            complete = false
                            skipped++
                            return@forEach
                        }
                        val relative = canonical.relativeTo(base).invariantSeparatorsPath
                        add(relative, child.name, child.isDirectory, if (child.isFile) child.length() else 0L,
                            child.lastModified(), mimeForName(child.name))
                        if (child.isDirectory) {
                            if (depth < MAX_DEPTH) stack.add(child to depth + 1)
                            else { complete = false; skipped++ }
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
                    val children = try { directory.listFiles() } catch (_: Exception) { null }
                    if (children == null) {
                        complete = false
                        skipped++
                        continue
                    }
                    children.forEach { child ->
                        val name = child.name ?: return@forEach
                        if (name.startsWith(".")) return@forEach
                        val relative = if (parentPath.isEmpty()) name else "$parentPath/$name"
                        add(relative, name, child.isDirectory, if (child.isFile) child.length() else 0L,
                            child.lastModified(), child.type ?: mimeForName(name))
                        if (child.isDirectory) {
                            if (depth < MAX_DEPTH) stack.add((child to relative) to depth + 1)
                            else { complete = false; skipped++ }
                        }
                    }
                }
            }
        }
        flush()
        // Never prune old rows after a partial traversal. This protects the last
        // known-good index when Android or a SAF provider temporarily denies access.
        if (complete) database.finishSource(volume, scanId)
    }

    fun status(): org.json.JSONObject {
        val counts = database.counts()
        return org.json.JSONObject()
            .put("state", state)
            .put("scanned", scanned)
            .put("skipped", skipped)
            .put("last_completed_at", lastCompletedAt)
            .put("last_error", lastError)
            .put("file_count", counts["files"] ?: 0)
            .put("media_count", counts["media"] ?: 0)
    }

    fun media(category: String, query: String, limit: Int, offset: Int) =
        database.queryMedia(category, query, limit, offset)

    fun files(query: String, limit: Int, offset: Int) =
        database.searchFiles(query, limit, offset)

    companion object {
        private const val MAX_DEPTH = 64
        private val AUDIO = setOf("mp3","m4a","aac","wav","flac","ogg","opus","wma","aiff","alac")
        private val VIDEO = setOf("mp4","m4v","mov","mkv","webm","avi","wmv","mpeg","mpg","3gp","ts","m2ts","mts","flv","f4v","3g2","m2v","ogv","vob","rmvb")
        private val PHOTO = setOf("jpg","jpeg","png","webp","gif","bmp","heic","heif","avif")

        private fun categoryFor(name: String): String? = when (name.substringAfterLast('.', "").lowercase()) {
            in AUDIO -> "music"
            in VIDEO -> "video"
            in PHOTO -> "photo"
            else -> null
        }

        private fun mimeForName(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
            "mp3" -> "audio/mpeg"; "m4a" -> "audio/mp4"; "aac" -> "audio/aac"; "flac" -> "audio/flac"
            "ogg","opus" -> "audio/ogg"; "wav" -> "audio/wav"; "mp4","m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"; "jpg","jpeg" -> "image/jpeg"; "png" -> "image/png"
            "webp" -> "image/webp"; "gif" -> "image/gif"; "pdf" -> "application/pdf"
            else -> "application/octet-stream"
        }
    }
}
