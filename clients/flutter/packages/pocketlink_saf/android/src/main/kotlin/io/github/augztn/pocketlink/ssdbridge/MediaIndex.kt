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

private val AUDIO_EXTENSIONS = setOf("mp3", "flac", "m4a", "wav", "ogg", "aac", "opus", "wma")
private val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "webm", "mov", "avi", "m4v", "3gp", "ts")
private val PHOTO_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "heif", "tif", "tiff", "avif")
private val AUDIO_MIME_TYPES = setOf(
    "audio/mpeg", "audio/flac", "audio/x-flac", "audio/mp4", "audio/x-m4a",
    "audio/wav", "audio/x-wav", "audio/ogg", "audio/aac", "audio/opus",
    "audio/x-ms-wma"
)
private val VIDEO_MIME_TYPES = setOf(
    "video/mp4", "video/x-m4v", "video/x-matroska", "video/webm",
    "video/quicktime", "video/x-msvideo", "video/3gpp", "video/mp2t"
)
private val PHOTO_MIME_TYPES = setOf(
    "image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp",
    "image/heic", "image/heif", "image/tiff", "image/avif"
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
        val (extensions, allowedMime) = when (category) {
            "music" -> AUDIO_EXTENSIONS to AUDIO_MIME_TYPES
            "video" -> VIDEO_EXTENSIONS to VIDEO_MIME_TYPES
            "photo" -> PHOTO_EXTENSIONS to PHOTO_MIME_TYPES
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

    fun sizeTotals(): Map<String, Long> {
        val db = readableDatabase
        fun total(table: String): Long = db.rawQuery("SELECT COALESCE(SUM(size), 0) FROM $table", null).use {
            if (it.moveToFirst()) it.getLong(0) else 0L
        }
        return mapOf("indexed_bytes" to total("files"), "media_bytes" to total("media"))
    }
}

internal class MediaIndexScanner(
    context: Context,
    private val internalRoot: () -> File,
    private val externalRoots: () -> List<Pair<String, DocumentFile>>
) {
    private val database = MediaIndexDatabase(context.applicationContext)
    private val reportPrefs = context.applicationContext.getSharedPreferences("media-index-report", Context.MODE_PRIVATE)
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PocketLink-MediaIndex").apply { isDaemon = true }
    }
    private val running = AtomicBoolean(false)
    private val dirty = AtomicBoolean(false)
    @Volatile private var started = false
    @Volatile private var lastAttemptStartedAt = reportPrefs.getLong(
        "last_attempt_started_at", readScanHistory().optJSONObject(0)?.optLong("started_at") ?: 0L
    )
    @Volatile private var lastAttemptFinishedAt = reportPrefs.getLong(
        "last_attempt_finished_at", readScanHistory().optJSONObject(0)?.optLong("completed_at") ?: 0L
    )
    @Volatile private var lastSuccessfulAt = reportPrefs.getLong(
        "last_successful_at",
        (0 until readScanHistory().length()).mapNotNull { index ->
            readScanHistory().optJSONObject(index)?.takeIf { it.optString("state") == "complete" }
                ?.optLong("completed_at")?.takeIf { it > 0L }
        }.maxOrNull() ?: 0L
    )
    @Volatile private var scanned = readScanHistory().optJSONObject(0)?.optInt("scanned") ?: 0
    @Volatile private var scannedDirectories = 0
    @Volatile private var unchanged = 0
    @Volatile private var skipped = readScanHistory().optJSONObject(0)?.optInt("skipped") ?: 0
    @Volatile private var state = if (lastAttemptStartedAt > lastAttemptFinishedAt) "interrupted" else
        (readScanHistory().optJSONObject(0)?.optString("state") ?: "idle")
    @Volatile private var lastError: String? = readScanHistory().optJSONObject(0)?.optString("last_error")?.takeIf { it.isNotBlank() }
    @Volatile private var lastCompletedAt: Long = readScanHistory().optJSONObject(0)?.optLong("completed_at") ?: 0L
    @Volatile private var lastScanStartedAt: Long = readScanHistory().optJSONObject(0)?.optLong("started_at") ?: 0L
    @Volatile private var scanRunId: String = readScanHistory().optJSONObject(0)?.optString("run_id").orEmpty()
    @Volatile private var scanTrigger: String = "automatic"
    @Volatile private var queuedTrigger: String? = null
    @Volatile private var lastScanTrigger: String = reportPrefs.getString("last_trigger", "automatic") ?: "automatic"
    @Volatile private var newFiles = readScanHistory().optJSONObject(0)?.optInt("new_files") ?: 0
    @Volatile private var updatedFiles = readScanHistory().optJSONObject(0)?.optInt("updated_files") ?: 0
    @Volatile private var scannedBytes = readScanHistory().optJSONObject(0)?.optLong("scanned_bytes") ?: 0L
    private val volumeReports = java.util.concurrent.ConcurrentHashMap<String, org.json.JSONObject>().apply {
        val previous = readScanHistory().optJSONObject(0)?.optJSONArray("volumes")
        if (previous != null) for (index in 0 until previous.length()) {
            val item = previous.optJSONObject(index) ?: continue
            put(item.optString("volume"), item)
        }
    }
    @Volatile private var currentSource: String? = null
    @Volatile private var currentPath: String? = null
    private val skippedItems = mutableListOf<SkippedIndexItem>().apply {
        val previous = readScanHistory().optJSONObject(0)?.optJSONArray("skipped_items")
        if (previous != null) for (index in 0 until previous.length()) {
            val item = previous.optJSONObject(index) ?: continue
            add(SkippedIndexItem(item.optString("volume"), item.optString("path"), item.optString("reason")))
        }
    }

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
        if (!started) {
            started = true
            if (automaticScanningEnabled() && reportPrefs.getBoolean("scan_on_startup", true)) {
                requestScan(force = false, trigger = "automatic")
            }
        } else if (automaticScanningEnabled() && dirty.get() && !running.get()) {
            requestScan(force = true, trigger = "automatic")
        }
    }

    fun automaticScanningEnabled(): Boolean =
        reportPrefs.getBoolean("automatic_scanning_enabled", true)

    fun scanIntervalMinutes(): Int =
        reportPrefs.getInt("scan_interval_minutes", 60).coerceIn(15, 1440)

    fun configureAutomaticScanning(
        enabled: Boolean,
        intervalMinutes: Int,
        scanOnStartup: Boolean = reportPrefs.getBoolean("scan_on_startup", true),
        scanOnStorageChange: Boolean = reportPrefs.getBoolean("scan_on_storage_change", true)
    ): org.json.JSONObject {
        val safeInterval = intervalMinutes.coerceIn(15, 1440)
        reportPrefs.edit()
            .putBoolean("automatic_scanning_enabled", enabled)
            .putBoolean("scan_on_startup", scanOnStartup)
            .putBoolean("scan_on_storage_change", scanOnStorageChange)
            .putInt("scan_interval_minutes", safeInterval)
            .apply()
        return automaticSettings()
    }

    fun automaticSettings(): org.json.JSONObject {
        val enabled = automaticScanningEnabled()
        val interval = scanIntervalMinutes()
        val baseline = lastCompletedAt.takeIf { it > 0L } ?: lastAttemptStartedAt
        return org.json.JSONObject()
            .put("enabled", enabled)
            .put("scan_on_startup", reportPrefs.getBoolean("scan_on_startup", true))
            .put("scan_on_storage_change", reportPrefs.getBoolean("scan_on_storage_change", true))
            .put("interval_minutes", interval)
            .put("next_scan_at", if (enabled && baseline > 0L) baseline + interval * 60_000L else 0L)
    }

    fun maybeRunScheduledScan() {
        if (!automaticScanningEnabled() || running.get()) return
        val baseline = lastCompletedAt.takeIf { it > 0L } ?: lastAttemptStartedAt
        if (baseline == 0L || System.currentTimeMillis() - baseline >= scanIntervalMinutes() * 60_000L) {
            requestScan(force = true, trigger = "automatic")
        }
    }

    fun runScheduledScanCheck() = maybeRunScheduledScan()

    fun onStorageChanged(connected: Boolean) {
        if (!connected) {
            // Never traverse a possibly detached SAF tree: some providers report
            // an empty directory on removal, which could otherwise prune valid rows.
            val externalReports = volumeReports.values.filter { it.optString("volume") != "internal" }
            externalReports.forEach { report ->
                report.put("state", "unavailable")
                    .put("stale", true)
                    .put("error", "Storage volume disconnected; indexed content is retained")
            }
            if (externalReports.isNotEmpty()) {
                state = "partial"
                lastError = "External storage disconnected; its indexed content is retained but may be stale."
            }
            dirty.set(true)
            return
        }
        volumeReports.values.filter { it.optString("volume") != "internal" }.forEach { report ->
            if (report.optString("state") == "unavailable") {
                report.put("state", "stale").put("stale", true)
            }
        }
        dirty.set(true)
        if (automaticScanningEnabled() && reportPrefs.getBoolean("scan_on_storage_change", true)) {
            requestScan(force = true, trigger = "automatic")
        }
    }

    fun retryFailedScan() {
        if (running.get()) return
        requestScan(force = true, trigger = "manual")
    }

    @Synchronized
    fun requestScan(force: Boolean, trigger: String = "manual") {
        if (running.get()) {
            // Coalesce refreshes and mutations into one follow-up pass.
            if (force) {
                dirty.set(true)
                queuedTrigger = trigger
            }
            return
        }
        if (started && !force && state == "complete") return
        started = true
        lastScanStartedAt = System.currentTimeMillis()
        lastAttemptStartedAt = lastScanStartedAt
        reportPrefs.edit().putLong("last_attempt_started_at", lastAttemptStartedAt).apply()
        scanTrigger = trigger
        scanRunId = UUID.randomUUID().toString()
        newFiles = 0
        updatedFiles = 0
        scannedBytes = 0L
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
                externalRoots()
                    .filterNot { (id, _) -> volumeReports[id]?.optString("state") == "unavailable" }
                    .forEach { (id, root) -> sources += id to root }
                val previousVolumes = volumeReports.values.map { org.json.JSONObject(it.toString()) }
                val activeVolumeIds = sources.map { it.first }.toSet()
                volumeReports.clear()
                previousVolumes.filter { it.optString("volume") !in activeVolumeIds }.forEach { previous ->
                    val volume = previous.optString("volume")
                    volumeReports[volume] = org.json.JSONObject()
                        .put("volume", volume)
                        .put("state", "unavailable")
                        .put("stale", true)
                        .put("last_scanned_at", previous.optLong("completed_at"))
                        .put("error", "Storage volume is disconnected or no longer accessible")
                }
                sources.forEach { (id, root) ->
                    currentSource = id
                    val skippedBefore = skipped
                    val scannedBefore = scanned
                    val startedAt = System.currentTimeMillis()
                    volumeReports[id] = org.json.JSONObject()
                        .put("volume", id).put("state", "scanning").put("started_at", startedAt)
                    try {
                        scanSource(id, root)
                        volumeReports[id] = org.json.JSONObject()
                            .put("volume", id)
                            .put("state", if (skipped == skippedBefore) "complete" else "partial")
                            .put("started_at", startedAt)
                            .put("completed_at", System.currentTimeMillis())
                            .put("scanned", scanned - scannedBefore)
                            .put("skipped", skipped - skippedBefore)
                    } catch (error: Exception) {
                        volumeReports[id] = org.json.JSONObject()
                            .put("volume", id).put("state", "failed")
                            .put("started_at", startedAt).put("completed_at", System.currentTimeMillis())
                            .put("error", error.message ?: "Storage source could not be indexed")
                        skipped++
                        recordSkipped(id, "", error.message ?: "Storage source could not be indexed")
                        lastError = error.message ?: "One storage source could not be indexed"
                    } finally {
                        currentSource = null
                        currentPath = null
                    }
                }
                val unavailableVolumes = volumeReports.values.any { it.optString("state") == "unavailable" }
                if (lastError == null && skipped > 0) lastError = "Some files or folders could not be indexed."
                if (lastError == null && unavailableVolumes) {
                    lastError = "One or more previously indexed storage volumes are disconnected; their indexed content may be stale."
                }
                state = if (lastError == null && skipped == 0 && !unavailableVolumes) "complete" else "partial"
                lastCompletedAt = System.currentTimeMillis()
                lastAttemptFinishedAt = lastCompletedAt
                reportPrefs.edit().putLong("last_attempt_finished_at", lastAttemptFinishedAt).apply()
                if (state == "complete") {
                    lastSuccessfulAt = lastCompletedAt
                    reportPrefs.edit().putLong("last_successful_at", lastSuccessfulAt).apply()
                }
                persistScanReport()
            } catch (error: Exception) {
                state = "failed"
                lastError = error.message ?: "Index scan failed"
                lastCompletedAt = System.currentTimeMillis()
                lastAttemptFinishedAt = lastCompletedAt
                reportPrefs.edit().putLong("last_attempt_finished_at", lastAttemptFinishedAt).apply()
                persistScanReport()
                currentSource = null
                currentPath = null
            } finally {
                val nextTrigger = synchronized(this) {
                    running.set(false)
                    val shouldRescan = dirty.getAndSet(false)
                    val trigger = queuedTrigger ?: scanTrigger
                    queuedTrigger = null
                    shouldRescan to trigger
                }
                if (nextTrigger.first) requestScan(force = true, trigger = nextTrigger.second)
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
            val category = if (directory) null else categoryFor(name, mime)
            scannedBytes += safeSize
            val previousFile = fileSnapshot[path]
            val previousMedia = mediaSnapshot[path]
            // Some SAF providers always report modified=0. In that case use
            // size + category as the best available stable fingerprint.
            val fileUnchanged = previousFile != null &&
                previousFile.size == safeSize &&
                (if (safeModified <= 0L) previousFile.modified <= 0L
                else previousFile.modified == safeModified)
            if (!directory) {
                if (previousFile == null) newFiles++
                else if (!fileUnchanged) updatedFiles++
            }
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
                if (!root.exists() || !root.isDirectory || !root.canRead()) {
                    throw IllegalStateException("Internal storage is unavailable or unreadable")
                }
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
                if (!root.exists() || !root.isDirectory) {
                    throw IllegalStateException("Storage volume is disconnected or unavailable")
                }
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
        val sizes = database.sizeTotals()
        val history = readScanHistory()
        return org.json.JSONObject()
            .put("state", state)
            .put("last_attempt_started_at", lastAttemptStartedAt)
            .put("last_attempt_finished_at", lastAttemptFinishedAt)
            .put("last_successful_at", lastSuccessfulAt)
            .put("timezone_id", java.util.TimeZone.getDefault().id)
            .put("scanned", scanned)
            .put("scanned_directories", scannedDirectories)
            .put("unchanged_count", unchanged)
            .put("indexed_count", (scanned - unchanged).coerceAtLeast(0))
            .put("skipped", skipped)
            .put("last_completed_at", lastCompletedAt)
            .put("last_scan_started_at", lastScanStartedAt)
            .put("scan_trigger", if (state == "scanning") scanTrigger else lastScanTrigger)
            .put("scan_run_id", scanRunId)
            .put("new_files", newFiles)
            .put("updated_files", updatedFiles)
            .put("scanned_bytes", scannedBytes)
            .put("volumes", org.json.JSONArray().also { items ->
                volumeReports.values.sortedBy { it.optString("volume") }.forEach { items.put(it) }
            })
            .put("scan_history", readScanHistory())
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
            .put("other_file_count", counts["other"] ?: 0)
            .put("indexed_bytes", sizes["indexed_bytes"] ?: 0L)
            .put("media_bytes", sizes["media_bytes"] ?: 0L)
            .put("automatic_scanning", automaticSettings())
            .put("duration_average_ms", run {
                val durations = (0 until history.length()).mapNotNull { index ->
                    history.optJSONObject(index)?.takeIf { it.optString("state") == "complete" }
                        ?.optLong("duration_ms")?.takeIf { it > 0L }
                }
                if (durations.isEmpty()) 0L else durations.average().toLong()
            })
            .put("duration_trend_percent", run {
                val completed = (0 until history.length()).mapNotNull { index ->
                    history.optJSONObject(index)?.takeIf { it.optString("state") == "complete" }
                        ?.optLong("duration_ms")?.takeIf { it > 0L }
                }
                if (completed.size < 2) 0 else {
                    val baseline = completed.drop(1).take(5).average()
                    if (baseline <= 0.0) 0 else (((completed.first() - baseline) / baseline) * 100.0).toInt()
                }
            })
    }

    private fun readScanHistory(): org.json.JSONArray = try {
        org.json.JSONArray(reportPrefs.getString("scan_history", "[]"))
    } catch (_: Exception) { org.json.JSONArray() }

    private fun persistScanReport() {
        lastScanTrigger = scanTrigger
        reportPrefs.edit().putString("last_trigger", lastScanTrigger).apply()
        val history = readScanHistory()
        val record = org.json.JSONObject()
            .put("run_id", scanRunId)
            .put("started_at", lastScanStartedAt)
            .put("completed_at", lastCompletedAt)
            .put("timezone_id", java.util.TimeZone.getDefault().id)
            .put("duration_ms", (lastCompletedAt - lastScanStartedAt).coerceAtLeast(0L))
            .put("trigger", lastScanTrigger)
            .put("state", state)
            .put("scanned", scanned)
            .put("skipped", skipped)
            .put("new_files", newFiles)
            .put("updated_files", updatedFiles)
            .put("scanned_bytes", scannedBytes)
            .put("last_error", lastError)
            .put("volumes", org.json.JSONArray().also { items ->
                volumeReports.values.sortedBy { it.optString("volume") }.forEach { items.put(it) }
            })
            .put("skipped_items", org.json.JSONArray().also { items ->
                synchronized(skippedItems) {
                    skippedItems.forEach { item ->
                        items.put(org.json.JSONObject().put("volume", item.volume).put("path", item.path).put("reason", item.reason))
                    }
                }
            })
        val next = org.json.JSONArray().put(record)
        for (index in 0 until minOf(history.length(), 19)) {
            next.put(history.getJSONObject(index))
        }
        reportPrefs.edit()
            .putString("scan_history", next.toString())
            .putLong("last_attempt_started_at", lastAttemptStartedAt)
            .putLong("last_attempt_finished_at", lastAttemptFinishedAt)
            .putLong("last_successful_at", lastSuccessfulAt)
            .apply()
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
        private const val MAX_DEPTH = 64
        private const val MAX_REPORTED_SKIPPED_ITEMS = 100
        private val PHOTO = setOf(
            "jpg","jpeg","png","webp","gif","bmp","heic","heif","avif",
            "tif","tiff","jxl","dng","cr2","nef","arw","orf","rw2"
        )

        private fun categoryFor(name: String, mime: String): String? {
            val extension = name.substringAfterLast('.', "").lowercase()
            val normalizedMime = mime.substringBefore(';').trim().lowercase()
            val genericMime = normalizedMime.isEmpty() || normalizedMime == "application/octet-stream"
            return when {
                extension in AUDIO_EXTENSIONS && (genericMime || normalizedMime in AUDIO_MIME_TYPES) -> "music"
                extension in VIDEO_EXTENSIONS && (genericMime || normalizedMime in VIDEO_MIME_TYPES) -> "video"
                extension in PHOTO -> "photo"
                else -> null
            }
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
                "js" to "text/javascript",
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
