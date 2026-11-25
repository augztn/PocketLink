package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.Collections

internal data class IndexDatabaseStats(
    val counts: Map<String, Int>,
    val sizes: Map<String, Long>
)

internal class MediaIndexDatabase(context: Context) :
    SQLiteOpenHelper(context, "pocketlink_index.db", null, 3) {

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
        createScanCheckpointTable(db)
        createScanTraversalTables(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) createScanCheckpointTable(db)
        if (oldVersion < 3) createScanTraversalTables(db)
    }

    private fun createScanCheckpointTable(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS scan_checkpoints (
                volume TEXT PRIMARY KEY NOT NULL,
                root_id TEXT NOT NULL,
                scan_id TEXT NOT NULL,
                state TEXT NOT NULL
            )
        """.trimIndent())
    }

    @Synchronized fun scanCheckpoint(volume: String): String? =
        readableDatabase.query(
            "scan_checkpoints", arrayOf("root_id", "scan_id", "state"),
            "volume=?", arrayOf(volume), null, null, null
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else org.json.JSONObject()
                .put("root_id", cursor.getString(0))
                .put("scan_id", cursor.getString(1))
                .put("state", cursor.getString(2))
                .toString()
        }

    @Synchronized fun saveScanCheckpoint(volume: String, rootId: String, scanId: String, state: String) {
        // Compatibility path for persisted v2 checkpoints and test fixtures.
        val legacy = org.json.JSONObject(state)
        val db = writableDatabase
        db.beginTransaction()
        try {
            val normalized = org.json.JSONObject()
                .put("normalized", true)
                .put("complete", legacy.optBoolean("complete", true))
                .put("files_healthy", legacy.optBoolean("files_healthy", true))
                .put("media_healthy", legacy.optBoolean("media_healthy", true))
            val values = android.content.ContentValues().apply {
                put("volume", volume); put("root_id", rootId); put("scan_id", scanId)
                put("state", normalized.toString())
            }
            db.insertWithOnConflict("scan_checkpoints", null, values, SQLiteDatabase.CONFLICT_REPLACE)
            db.delete("scan_pending", "volume=?", arrayOf(volume))
            db.delete("scan_visited", "volume=?", arrayOf(volume))
            val pending = legacy.optJSONArray("pending")
            if (pending != null) {
                val statement = db.compileStatement("INSERT INTO scan_pending(volume,scan_id,path) VALUES(?,?,?)")
                try { for (i in 0 until pending.length()) {
                    statement.clearBindings(); statement.bindString(1, volume); statement.bindString(2, scanId)
                    statement.bindString(3, pending.optString(i)); statement.executeInsert()
                } } finally { statement.close() }
            }
            val visited = legacy.optJSONArray("visited")
            if (visited != null) {
                val statement = db.compileStatement("INSERT OR IGNORE INTO scan_visited(volume,scan_id,identity) VALUES(?,?,?)")
                try { for (i in 0 until visited.length()) {
                    statement.clearBindings(); statement.bindString(1, volume); statement.bindString(2, scanId)
                    statement.bindString(3, visited.optString(i)); statement.executeInsert()
                } } finally { statement.close() }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    @Synchronized fun clearScanCheckpoint(volume: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("scan_checkpoints", "volume=?", arrayOf(volume))
            db.delete("scan_pending", "volume=?", arrayOf(volume))
            db.delete("scan_visited", "volume=?", arrayOf(volume))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    @Synchronized fun hasScanCheckpoints(): Boolean =
        readableDatabase.rawQuery("SELECT 1 FROM scan_checkpoints LIMIT 1", null).use { it.moveToFirst() }

    private fun createScanTraversalTables(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS scan_pending (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                volume TEXT NOT NULL,
                scan_id TEXT NOT NULL,
                path TEXT NOT NULL
            )
        """.trimIndent())
        db.execSQL("CREATE INDEX IF NOT EXISTS scan_pending_order_idx ON scan_pending(volume, scan_id, id DESC)")
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS scan_visited (
                volume TEXT NOT NULL,
                scan_id TEXT NOT NULL,
                identity TEXT NOT NULL,
                PRIMARY KEY(volume, scan_id, identity)
            )
        """.trimIndent())
    }

    data class PendingDirectory(val id: Long, val path: String)

    @Synchronized fun beginScanCheckpoint(
        volume: String, rootId: String, scanId: String, initialPath: String = ""
    ) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val state = org.json.JSONObject()
                .put("normalized", true)
                .put("complete", true)
                .put("files_healthy", true)
                .put("media_healthy", true)
            val values = android.content.ContentValues().apply {
                put("volume", volume)
                put("root_id", rootId)
                put("scan_id", scanId)
                put("state", state.toString())
            }
            db.insertWithOnConflict("scan_checkpoints", null, values, SQLiteDatabase.CONFLICT_REPLACE)
            db.delete("scan_pending", "volume=?", arrayOf(volume))
            db.delete("scan_visited", "volume=?", arrayOf(volume))
            val pending = android.content.ContentValues().apply {
                put("volume", volume); put("scan_id", scanId); put("path", initialPath)
            }
            db.insertOrThrow("scan_pending", null, pending)
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    @Synchronized fun pendingBatch(volume: String, scanId: String, limit: Int): List<PendingDirectory> {
        val result = mutableListOf<PendingDirectory>()
        readableDatabase.query(
            "scan_pending", arrayOf("id", "path"), "volume=? AND scan_id=?",
            arrayOf(volume, scanId), null, null, "id DESC", limit.toString()
        ).use { cursor ->
            while (cursor.moveToNext()) result += PendingDirectory(cursor.getLong(0), cursor.getString(1))
        }
        return result
    }

    @Synchronized fun hasVisited(volume: String, scanId: String, identity: String): Boolean =
        readableDatabase.query(
            "scan_visited", arrayOf("identity"),
            "volume=? AND scan_id=? AND identity=?",
            arrayOf(volume, scanId, identity), null, null, null, "1"
        ).use { it.moveToFirst() }

    @Synchronized fun commitScanBatch(
        volume: String,
        scanId: String,
        consumedIds: List<Long>,
        pendingPaths: List<String>,
        visitedIdentities: Set<String>,
        complete: Boolean,
        filesHealthy: Boolean,
        mediaHealthy: Boolean
    ) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            // Stay below SQLite's bind-parameter limit on older Android releases.
            consumedIds.chunked(500).forEach { idBatch ->
                val placeholders = idBatch.joinToString(",") { "?" }
                val selectionArgs = mutableListOf(volume, scanId).apply {
                    addAll(idBatch.map { it.toString() })
                }
                db.delete("scan_pending", "volume=? AND scan_id=? AND id IN ($placeholders)",
                    selectionArgs.toTypedArray())
            }
            val pendingStatement = db.compileStatement(
                "INSERT INTO scan_pending(volume,scan_id,path) VALUES(?,?,?)"
            )
            try {
                pendingPaths.forEach { path ->
                    pendingStatement.clearBindings()
                    pendingStatement.bindString(1, volume)
                    pendingStatement.bindString(2, scanId)
                    pendingStatement.bindString(3, path)
                    pendingStatement.executeInsert()
                }
            } finally { pendingStatement.close() }
            val visitedStatement = db.compileStatement(
                "INSERT OR IGNORE INTO scan_visited(volume,scan_id,identity) VALUES(?,?,?)"
            )
            try {
                visitedIdentities.forEach { identity ->
                    visitedStatement.clearBindings()
                    visitedStatement.bindString(1, volume)
                    visitedStatement.bindString(2, scanId)
                    visitedStatement.bindString(3, identity)
                    visitedStatement.executeInsert()
                }
            } finally { visitedStatement.close() }
            val state = org.json.JSONObject()
                .put("normalized", true)
                .put("complete", complete)
                .put("files_healthy", filesHealthy)
                .put("media_healthy", mediaHealthy)
            val values = android.content.ContentValues().apply { put("state", state.toString()) }
            db.update("scan_checkpoints", values, "volume=? AND scan_id=?", arrayOf(volume, scanId))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    @Synchronized fun checkpointHasPending(volume: String, scanId: String): Boolean =
        readableDatabase.rawQuery(
            "SELECT 1 FROM scan_pending WHERE volume=? AND scan_id=? LIMIT 1",
            arrayOf(volume, scanId)
        ).use { it.moveToFirst() }

    @Synchronized fun upsertFiles(batch: List<IndexedFile>, scanId: String) {
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

    @Synchronized fun upsertMedia(batch: List<IndexedFile>, scanId: String) {
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

    @Synchronized fun finishFilesSource(volume: String, scanId: String) {
        writableDatabase.delete("files", "volume=? AND scan_id<>?", arrayOf(volume, scanId))
    }

    @Synchronized fun finishMediaSource(volume: String, scanId: String) {
        writableDatabase.delete("media", "volume=? AND scan_id<>?", arrayOf(volume, scanId))
    }

    @Synchronized fun fileSnapshot(volume: String, paths: Collection<String>): Map<String, IndexStamp> {
        if (paths.isEmpty()) return emptyMap()
        val requested = paths.distinct()
        val placeholders = requested.joinToString(",") { "?" }
        val args = arrayOf(volume) + requested.toTypedArray()
        val result = mutableMapOf<String, IndexStamp>()
        readableDatabase.query(
            "files", arrayOf("path", "size", "modified"),
            "volume=? AND path IN ($placeholders)", args, null, null, null
        ).use { cursor ->
            while (cursor.moveToNext()) result[cursor.getString(0)] =
                IndexStamp(cursor.getLong(1), cursor.getLong(2))
        }
        return result
    }

    @Synchronized fun mediaSnapshot(volume: String, paths: Collection<String>): Map<String, IndexStamp> {
        if (paths.isEmpty()) return emptyMap()
        val requested = paths.distinct()
        val placeholders = requested.joinToString(",") { "?" }
        val args = arrayOf(volume) + requested.toTypedArray()
        val result = mutableMapOf<String, IndexStamp>()
        readableDatabase.query(
            "media", arrayOf("path", "size", "modified", "category"),
            "volume=? AND path IN ($placeholders)", args, null, null, null
        ).use { cursor ->
            while (cursor.moveToNext()) result[cursor.getString(0)] =
                IndexStamp(cursor.getLong(1), cursor.getLong(2), cursor.getString(3))
        }
        return result
    }

    @Synchronized fun hasIndexedDescendants(volume: String, parentPath: String): Boolean {
        val prefix = if (parentPath.isEmpty()) "" else "$parentPath/"
        return readableDatabase.rawQuery(
            """SELECT 1 FROM files
                WHERE volume=? AND path<>? AND substr(path,1,?)=?
                UNION ALL
                SELECT 1 FROM media
                WHERE volume=? AND path<>? AND substr(path,1,?)=?
                LIMIT 1""".trimIndent(),
            arrayOf(
                volume, parentPath, prefix.length.toString(), prefix,
                volume, parentPath, prefix.length.toString(), prefix
            )
        ).use { it.moveToFirst() }
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

    @Synchronized private fun markSeen(table: String, volume: String, paths: List<String>, scanId: String) {
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
        val (extensions, allowedMime) = when (category) {
            "music" -> MediaFileClassifier.AUDIO_EXTENSIONS to MediaFileClassifier.AUDIO_MIME_TYPES
            "video" -> MediaFileClassifier.VIDEO_EXTENSIONS to MediaFileClassifier.VIDEO_MIME_TYPES
            "photo" -> MediaFileClassifier.PHOTO_EXTENSIONS to MediaFileClassifier.PHOTO_MIME_TYPES
            else -> return emptyList()
        }
        val extensionClause = extensions.joinToString(" OR ") { "LOWER(name) LIKE ?" }
        val where = mutableListOf(
            "category=?",
            "($extensionClause)",
            "(LOWER(mime) IN (${allowedMime.joinToString(",") { "?" }}) OR LOWER(mime)=?)"
        )
        val args = mutableListOf(category)
        extensions.sorted().forEach { args += "%.$it" }
        allowedMime.sorted().forEach { args += it }
        args += "application/octet-stream"
        if (query.isNotBlank()) {
            val escaped = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            where += "(name LIKE ? ESCAPE '\\' OR path LIKE ? ESCAPE '\\')"
            args += escaped
            args += escaped
        }
        val rows = mutableListOf<IndexedFile>()
        readableDatabase.query(
            "media", arrayOf("volume","path","name","category","size","modified","mime"),
            where.joinToString(" AND "), args.toTypedArray(), null, null,
            "name COLLATE NOCASE ASC", "$offset,$limit"
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

    @Synchronized fun counts(): Map<String, Int> {
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
        val regularFiles = countType("file")
        val mediaFiles = count("media")
        return mapOf(
            "files" to count("files"),
            "directories" to countType("directory"),
            "regular_files" to regularFiles,
            "media" to mediaFiles,
            "photo" to countCategory("photo"),
            "video" to countCategory("video"),
            "music" to countCategory("music"),
            "other" to (regularFiles - mediaFiles).coerceAtLeast(0)
        )
    }

    // Hold one monitor across both aggregate queries; every write path uses this monitor too.
    @Synchronized fun statsSnapshot(): IndexDatabaseStats = IndexDatabaseStats(
        counts = Collections.unmodifiableMap(counts()),
        sizes = Collections.unmodifiableMap(sizeTotals())
    )

    @Synchronized fun sizeTotals(): Map<String, Long> {
        val db = readableDatabase
        fun total(table: String): Long = db.rawQuery("SELECT COALESCE(SUM(size), 0) FROM $table", null).use {
            if (it.moveToFirst()) it.getLong(0) else 0L
        }
        return mapOf("indexed_bytes" to total("files"), "media_bytes" to total("media"))
    }
}
