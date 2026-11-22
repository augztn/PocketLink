package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
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

/** True when a previously indexed descendant would be lost by accepting an empty listing. */
internal fun hasIndexedDescendants(indexedPaths: Set<String>, parentPath: String): Boolean {
    val prefix = if (parentPath.isEmpty()) "" else "$parentPath/"
    return indexedPaths.any { it.startsWith(prefix) && it != parentPath }
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
    private val closeRequested = AtomicBoolean(false)
    private val databaseClosed = AtomicBoolean(false)
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
    @Volatile private var lastScanStartedAt: Long = reportPrefs.getLong(
        "last_attempt_started_at", readScanHistory().optJSONObject(0)?.optLong("started_at") ?: 0L
    )
    @Volatile private var scanRunId: String = reportPrefs.getString(
        "last_attempt_run_id", readScanHistory().optJSONObject(0)?.optString("run_id").orEmpty()
    ) ?: ""
    @Volatile private var scanTrigger: String = reportPrefs.getString("last_attempt_trigger", "automatic") ?: "automatic"
    @Volatile private var queuedTrigger: String? = null
    @Volatile private var lastScanTrigger: String = reportPrefs.getString("last_trigger", "automatic") ?: "automatic"
    @Volatile private var newFiles = readScanHistory().optJSONObject(0)?.optInt("new_files") ?: 0
    @Volatile private var updatedFiles = readScanHistory().optJSONObject(0)?.optInt("updated_files") ?: 0
    @Volatile private var scannedBytes = readScanHistory().optJSONObject(0)?.optLong("scanned_bytes") ?: 0L
    private val disconnectedVolumes = java.util.Collections.newSetFromMap(
        java.util.concurrent.ConcurrentHashMap<String, Boolean>()
    ).apply {
        addAll(reportPrefs.getStringSet("disconnected_volumes", emptySet()) ?: emptySet())
    }
    private val volumeReports = java.util.concurrent.ConcurrentHashMap<String, org.json.JSONObject>().apply {
        val previous = readScanHistory().optJSONObject(0)?.optJSONArray("volumes")
        if (previous != null) for (index in 0 until previous.length()) {
            val item = previous.optJSONObject(index) ?: continue
            put(item.optString("volume"), org.json.JSONObject(item.toString()))
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

    private val scanScheduler by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        MediaIndexScanScheduler(
            preferences = reportPrefs,
            isScanning = { state == "scanning" },
            isRunning = { running.get() },
            lastScanStartedAt = { lastScanStartedAt },
            lastCompletedAt = { lastCompletedAt },
            lastAttemptStartedAt = { lastAttemptStartedAt },
            requestScan = { force, trigger -> requestScan(force, trigger) }
        )
    }

    init {
        disconnectedVolumes.forEach { volume ->
            volumeReports[volume]?.let { previous ->
                volumeReports[volume] = org.json.JSONObject(previous.toString())
                    .put("state", "unavailable")
                    .put("stale", true)
                    .put("error", "Storage volume disconnected; indexed content is retained")
            }
        }
        if (disconnectedVolumes.isNotEmpty() && volumeReports.isNotEmpty() && state != "interrupted") {
            state = "partial"
            lastError = "External storage disconnected; its indexed content is retained but may be stale."
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
        if (closeRequested.get()) return
        if (!started) {
            started = true
            if (scanScheduler.automaticScanningEnabled() && scanScheduler.scanOnStartupEnabled()) {
                requestScan(force = true, trigger = "automatic")
            } else {
                scanScheduler.ensureScheduleAnchor()
            }
        } else if (automaticScanningEnabled() && dirty.get() && !running.get()) {
            requestScan(force = true, trigger = "automatic")
        }
    }

    fun automaticScanningEnabled(): Boolean =
        scanScheduler.automaticScanningEnabled()

    fun scanIntervalMinutes(): Int = scanScheduler.scanIntervalMinutes()

    fun configureAutomaticScanning(
        enabled: Boolean,
        intervalMinutes: Int,
        scanOnStartup: Boolean = scanScheduler.scanOnStartupEnabled(),
        scanOnStorageChange: Boolean = scanScheduler.scanOnStorageChangeEnabled()
    ): org.json.JSONObject = scanScheduler.configure(
        enabled, intervalMinutes, scanOnStartup, scanOnStorageChange
    )

    fun automaticSettings(): org.json.JSONObject = scanScheduler.settings()

    fun maybeRunScheduledScan() = scanScheduler.maybeRunScheduledScan()

    fun runScheduledScanCheck() = maybeRunScheduledScan()

    fun onStorageChanged(connected: Boolean, volumeId: String? = null) {
        if (!connected) {
            // Never traverse a possibly detached SAF tree: some providers report
            // an empty directory on removal, which could otherwise prune valid rows.
            val externalIds = if (volumeId != null && volumeReports.containsKey(volumeId)) {
                mutableSetOf(volumeId)
            } else {
                volumeReports.values.map { it.optString("volume") }
                    .filter { it.isNotBlank() && it != "internal" }.toMutableSet()
            }
            currentSource?.takeIf { it != "internal" }?.let { externalIds.add(it) }
            disconnectedVolumes.addAll(externalIds)
            reportPrefs.edit().putStringSet("disconnected_volumes", disconnectedVolumes.toSet()).apply()
            externalIds.forEach { id ->
                volumeReports[id]?.let { previous ->
                    volumeReports[id] = org.json.JSONObject(previous.toString())
                        .put("state", "unavailable")
                        .put("stale", true)
                        .put("error", "Storage volume disconnected; indexed content is retained")
                }
            }
            if (externalIds.isNotEmpty()) {
                state = "partial"
                lastError = "External storage disconnected; its indexed content is retained but may be stale."
            }
            dirty.set(true)
            return
        }
        if (volumeId == null) disconnectedVolumes.clear() else disconnectedVolumes.remove(volumeId)
        reportPrefs.edit().putStringSet("disconnected_volumes", disconnectedVolumes.toSet()).apply()
        val reconnectingIds = if (volumeId == null) volumeReports.keys.toList() else listOf(volumeId)
        reconnectingIds.forEach { id ->
            volumeReports[id]?.let { previous ->
                if (previous.optString("volume") != "internal" && previous.optString("state") == "unavailable") {
                    volumeReports[id] = org.json.JSONObject(previous.toString())
                        .put("state", "stale").put("stale", true)
                }
            }
        }
        dirty.set(true)
        if (scanScheduler.automaticScanningEnabled() && scanScheduler.scanOnStorageChangeEnabled()) {
            requestScan(force = true, trigger = "automatic")
        }
    }

    fun retryFailedScan() {
        if (running.get()) return
        requestScan(force = true, trigger = "manual")
    }

    @Synchronized
    fun requestScan(force: Boolean, trigger: String = "manual") {
        if (closeRequested.get()) return
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
        scanTrigger = trigger
        scanRunId = UUID.randomUUID().toString()
        reportPrefs.edit()
            .putLong("last_attempt_started_at", lastAttemptStartedAt)
            .putString("last_attempt_trigger", scanTrigger)
            .putString("last_attempt_run_id", scanRunId)
            .apply()
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
                    .filterNot { (id, _) -> id in disconnectedVolumes || volumeReports[id]?.optString("state") == "unavailable" }
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
                        if (closeRequested.get()) return@execute
                        volumeReports[id] = org.json.JSONObject()
                            .put("volume", id)
                            .put("state", when {
                                id in disconnectedVolumes -> "unavailable"
                                skipped == skippedBefore -> "complete"
                                else -> "partial"
                            })
                            .put("stale", id in disconnectedVolumes)
                            .put("started_at", startedAt)
                            .put("completed_at", System.currentTimeMillis())
                            .put("scanned", scanned - scannedBefore)
                            .put("skipped", skipped - skippedBefore)
                            .also { report ->
                                if (id in disconnectedVolumes) {
                                    report.put("error", "Storage disconnected during scan; previous index retained")
                                }
                            }
                    } catch (error: Exception) {
                        if (closeRequested.get()) return@execute
                        volumeReports[id] = org.json.JSONObject()
                            .put("volume", id)
                            .put("state", if (id in disconnectedVolumes) "unavailable" else "failed")
                            .put("stale", id in disconnectedVolumes)
                            .put("started_at", startedAt).put("completed_at", System.currentTimeMillis())
                            .put("error", if (id in disconnectedVolumes) "Storage disconnected during scan; previous index retained" else error.message ?: "Storage source could not be indexed")
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
                if (!closeRequested.get()) {
                    state = "failed"
                    lastError = error.message ?: "Index scan failed"
                    lastCompletedAt = System.currentTimeMillis()
                    lastAttemptFinishedAt = lastCompletedAt
                    reportPrefs.edit().putLong("last_attempt_finished_at", lastAttemptFinishedAt).apply()
                    persistScanReport()
                }
                currentSource = null
                currentPath = null
            } finally {
                val nextTrigger = synchronized(this) {
                    running.set(false)
                    val shouldRescan = !closeRequested.get() && dirty.getAndSet(false)
                    val trigger = queuedTrigger ?: scanTrigger
                    queuedTrigger = null
                    shouldRescan to trigger
                }
                if (nextTrigger.first && !closeRequested.get()) {
                    requestScan(force = true, trigger = nextTrigger.second)
                }
                if (closeRequested.get()) closeDatabase()
            }
        }
    }

    private fun ensureScanActive() {
        if (closeRequested.get() || Thread.currentThread().isInterrupted) {
            throw InterruptedException("Media index scan cancelled during host shutdown")
        }
    }

    private fun scanSource(volume: String, root: Any) {
        ensureScanActive()
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
            val category = if (directory) null else MediaFileClassifier.categoryFor(name, mime)
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
                    ensureScanActive()
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
                        ensureScanActive()
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
                            child.lastModified(), MediaFileClassifier.mimeForName(child.name))
                        if (child.isDirectory) {
                            if (depth < MAX_DEPTH) stack.add(child to depth + 1)
                            else { complete = false; skipped++; recordSkipped(volume, relative, "Maximum folder depth reached") }
                        }
                    }
                }
            }
            is DocumentFile -> {
                if (!root.exists() || !root.isDirectory || !root.canRead()) {
                    throw IllegalStateException("Storage volume is disconnected, unavailable, or unreadable")
                }
                val stack = ArrayDeque<Pair<Pair<DocumentFile, String>, Int>>()
                stack.add((root to "") to 0)
                while (stack.isNotEmpty()) {
                    ensureScanActive()
                    val (entry, depth) = stack.removeLast()
                    val (directory, parentPath) = entry
                    currentPath = parentPath
                    scannedDirectories++
                    if (!directory.canRead()) {
                        complete = false
                        skipped++
                        recordSkipped(volume, parentPath, "Folder could not be read")
                        continue
                    }
                    val children = try { directory.listFiles() } catch (_: Exception) { null }
                    if (children == null) {
                        complete = false
                        skipped++
                        recordSkipped(volume, parentPath, "Folder could not be read")
                        continue
                    }
                    if (children.isEmpty() && hasIndexedDescendants(fileSnapshot.keys + mediaSnapshot.keys, parentPath)) {
                        // SAF providers may report an empty array on transient query failures.
                        // An empty listing cannot prove deletion when prior descendants exist.
                        complete = false
                        skipped++
                        recordSkipped(volume, parentPath, "Storage provider returned an empty listing; previous entries were retained")
                        continue
                    }
                    children.forEach { child ->
                        ensureScanActive()
                        val name = child.name ?: run {
                            complete = false
                            skipped++
                            recordSkipped(volume, parentPath, "Storage provider returned an item without a name")
                            return@forEach
                        }
                        if (name.startsWith(".")) return@forEach
                        val relative = if (parentPath.isEmpty()) name else "$parentPath/$name"
                        add(relative, name, child.isDirectory, if (child.isFile) child.length() else 0L,
                            child.lastModified(), child.type ?: MediaFileClassifier.mimeForName(name))
                        if (child.isDirectory) {
                            if (depth < MAX_DEPTH) stack.add((child to relative) to depth + 1)
                            else { complete = false; skipped++; recordSkipped(volume, relative, "Maximum folder depth reached") }
                        }
                    }
                }
            }
        }
        ensureScanActive()
        flush()
        ensureScanActive()
        if (volume in disconnectedVolumes) {
            complete = false
            skipped++
            recordSkipped(volume, "", "Storage volume disconnected during scan")
            lastError = "A storage volume disconnected during scanning; its previous index was retained."
        }
        // Serialize final pruning with close(): shutdown either starts after this
        // commit or prevents it entirely, so a cancelled traversal cannot prune rows.
        synchronized(this) {
            ensureScanActive()
            // Each index is committed and pruned independently. A media-index
            // failure must not invalidate the general file index, or vice versa.
            if (complete && filesHealthy) database.finishFilesSource(volume, scanId)
            ensureScanActive()
            if (complete && mediaHealthy) database.finishMediaSource(volume, scanId)
        }
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
            .put("timezone_offset_minutes", java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60_000)
            .put("scanned", scanned)
            .put("scanned_directories", scannedDirectories)
            .put("unchanged_count", unchanged)
            .put("indexed_count", (scanned - unchanged).coerceAtLeast(0))
            .put("skipped", skipped)
            .put("last_completed_at", lastCompletedAt)
            .put("last_scan_started_at", lastScanStartedAt)
            .put("scan_trigger", if (state == "scanning" || state == "interrupted") scanTrigger else lastScanTrigger)
            .put("scan_run_id", scanRunId)
            .put("new_files", newFiles)
            .put("updated_files", updatedFiles)
            .put("scanned_bytes", scannedBytes)
            .put("volumes", org.json.JSONArray().also { items ->
                volumeReports.values.sortedBy { it.optString("volume") }
                    .forEach { items.put(org.json.JSONObject(it.toString())) }
            })
            .put("scan_history", readScanHistory())
            .put("elapsed_ms", when (state) {
                "scanning" -> System.currentTimeMillis() - lastScanStartedAt
                "interrupted" -> (System.currentTimeMillis() - lastAttemptStartedAt).coerceAtLeast(0L)
                else -> (lastCompletedAt - lastScanStartedAt).coerceAtLeast(0L)
            })
            .put("current_source", currentSource)
            .put("current_path", currentPath)
            .put("last_error", if (state == "interrupted") {
                "The host restarted before the previous scan finished. Run a new scan to reconcile the index."
            } else lastError)
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
            .put("last_automatic_scan_at", run {
                (0 until history.length()).mapNotNull { index ->
                    history.optJSONObject(index)?.takeIf { it.optString("trigger") == "automatic" }
                        ?.optLong("completed_at")?.takeIf { it > 0L }
                }.firstOrNull() ?: 0L
            })
            .put("last_manual_scan_at", run {
                (0 until history.length()).mapNotNull { index ->
                    history.optJSONObject(index)?.takeIf { it.optString("trigger") == "manual" }
                        ?.optLong("completed_at")?.takeIf { it > 0L }
                }.firstOrNull() ?: 0L
            })
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
            .put("timezone_offset_minutes", java.util.TimeZone.getDefault().getOffset(lastCompletedAt) / 60_000)
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
                volumeReports.values.sortedBy { it.optString("volume") }
                    .forEach { items.put(org.json.JSONObject(it.toString())) }
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

    /** Stop accepting scans and close SQLite only after the worker has exited. */
    fun close() {
        val pendingTasks = synchronized(this) {
            if (!closeRequested.compareAndSet(false, true)) return
            dirty.set(false)
            queuedTrigger = null
            executor.shutdownNow()
        }
        // A queued scan never started, so no worker can run its finally block.
        // An active scan closes the database itself when its cancellation check exits.
        if (pendingTasks.isNotEmpty() || !running.get()) closeDatabase()
    }

    private fun closeDatabase() {
        if (databaseClosed.compareAndSet(false, true)) database.close()
    }

    companion object {
        private const val MAX_DEPTH = 64
        private const val MAX_REPORTED_SKIPPED_ITEMS = 100

    }
}
