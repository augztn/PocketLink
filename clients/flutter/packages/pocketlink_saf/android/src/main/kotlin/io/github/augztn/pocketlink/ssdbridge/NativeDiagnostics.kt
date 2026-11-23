package io.github.augztn.pocketlink.ssdbridge

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Small persistent native-side diagnostic journal.
 *
 * Events contain operational metadata only. Sensitive field names and private
 * paths are redacted before persistence; the journal is bounded to 512 KiB
 * plus one rotated backup.
 */
internal object NativeDiagnostics {
    private const val MAX_BYTES = 512 * 1024
    private const val MAX_BACKUP_BYTES = 512 * 1024
    private val lock = Any()
    @Volatile private var file: File? = null
    private val sessionId = "native-" + UUID.randomUUID().toString()

    fun initialize(context: Context) {
        synchronized(lock) {
            if (file == null) {
                file = File(context.filesDir, "pocketlink-native.log")
            }
        }
    }

    fun record(
        level: String,
        category: String,
        component: String,
        message: String,
        fields: Map<String, Any?> = emptyMap(),
        error: Throwable? = null
    ) {
        val target = file ?: return
        synchronized(lock) {
            try {
                rotateIfNeeded(target)
                val timestamp = System.currentTimeMillis()
                val event = JSONObject()
                    .put("event_id", "$sessionId-${UUID.randomUUID()}")
                    .put("session_id", sessionId)
                    .put("timestamp", timestamp)
                    .put("level", level)
                    .put("category", sanitize(category))
                    .put("component", sanitize(component))
                    .put("message", sanitize(message))
                    .put("fields", sanitizeFields(fields))
                if (error != null) {
                    event.put("error", sanitize(error.message ?: error.javaClass.simpleName))
                    event.put("error_type", error.javaClass.simpleName)
                    event.put("stack_trace", sanitize(error.stackTraceToString()))
                }
                target.parentFile?.mkdirs()
                target.appendText("$event\n", Charsets.UTF_8)
            } catch (_: Exception) {
                // Diagnostics must never interrupt host service or storage work.
            }
        }
    }

    fun read(): String = synchronized(lock) {
        val target = file ?: return@synchronized ""
        buildString {
            val backup = File(target.path + ".1")
            if (backup.isFile) append(runCatching { backup.readText(Charsets.UTF_8) }.getOrDefault(""))
            if (target.isFile) append(runCatching { target.readText(Charsets.UTF_8) }.getOrDefault(""))
        }
    }

    fun clear() {
        synchronized(lock) {
            val target = file ?: return
            runCatching { target.writeText("", Charsets.UTF_8) }
            runCatching { File(target.path + ".1").delete() }
        }
    }

    private fun rotateIfNeeded(target: File) {
        if (!target.isFile || target.length() < MAX_BYTES) return
        val backup = File(target.path + ".1")
        if (backup.exists()) backup.delete()
        if (!target.renameTo(backup)) return
        if (backup.length() > MAX_BACKUP_BYTES) {
            val bytes = backup.readBytes().takeLast(MAX_BACKUP_BYTES)
            val firstLine = bytes.indexOf(10)
            backup.writeBytes(if (firstLine >= 0) bytes.drop(firstLine + 1).toByteArray() else bytes)
        }
        target.createNewFile()
    }

    private fun sanitizeFields(fields: Map<String, Any?>): JSONObject {
        val result = JSONObject()
        fields.forEach { (key, value) ->
            val normalized = key.replace(Regex("([A-Z])"), "_$1").lowercase()
            when {
                SENSITIVE_KEY.containsMatchIn(normalized) -> result.put(key, "[REDACTED]")
                PRIVATE_PATH_KEY.containsMatchIn(normalized) -> result.put(key, "[REDACTED_PATH]")
                else -> result.put(key, sanitizeValue(value))
            }
        }
        return result
    }

    private fun sanitizeValue(value: Any?): Any? = when (value) {
        null -> JSONObject.NULL
        is String -> sanitize(value)
        is Number, is Boolean -> value
        is Map<*, *> -> {
            val nested = JSONObject()
            value.forEach { (key, item) ->
                val name = key?.toString() ?: return@forEach
                val normalized = name.replace(Regex("([A-Z])"), "_$1").lowercase()
                nested.put(name, when {
                    SENSITIVE_KEY.containsMatchIn(normalized) -> "[REDACTED]"
                    PRIVATE_PATH_KEY.containsMatchIn(normalized) -> "[REDACTED_PATH]"
                    else -> sanitizeValue(item)
                })
            }
            nested
        }
        is Iterable<*> -> JSONArray().also { array -> value.forEach { array.put(sanitizeValue(it)) } }
        else -> sanitize(value.toString())
    }

    private fun sanitize(value: String): String {
        val withoutUrlHosts = value.replace(
            Regex("""\b((?:https?|wss?)://)(?:[^/@\s]+@)?(?:\[[^]]+]|[^:/?#\s]+)(?::\d+)?""", RegexOption.IGNORE_CASE),
            "$1[REDACTED_HOST]"
        )
        return withoutUrlHosts
            .replace(Regex("""(?<![:\w])/(?:data|storage|sdcard|mnt|home|users|private|var|tmp|opt)/[^\s,;)}\]]+""", RegexOption.IGNORE_CASE), "[REDACTED_PATH]")
            .replace(Regex("""(?<![\d.])(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?![\d.])"""), "[REDACTED_HOST]")
            .replace(Regex("""(?i)(password|passwd|authorization|token|secret|api[_-]?key)\s*[:=]\s*[^,;\s}]+"""), "$1=[REDACTED]")
    }

    private val SENSITIVE_KEY = Regex(
        "password|passwd|authorization|token|secret|api[_-]?key|username|cookie|host|hostname|address|server",
        RegexOption.IGNORE_CASE
    )
    private val PRIVATE_PATH_KEY = Regex(
        "(^|[_-])(path|filename|directory|folder|uri)([_-]|$)",
        RegexOption.IGNORE_CASE
    )

    internal fun initializeForTesting(target: File) {
        synchronized(lock) {
            file = target
            target.parentFile?.mkdirs()
            target.writeText("", Charsets.UTF_8)
        }
    }
}
