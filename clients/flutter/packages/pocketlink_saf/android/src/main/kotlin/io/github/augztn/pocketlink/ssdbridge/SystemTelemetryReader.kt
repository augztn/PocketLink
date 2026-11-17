package io.github.augztn.pocketlink.ssdbridge

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import org.json.JSONObject
import java.io.File

/**
 * Reads a lightweight, point-in-time snapshot of public Android system metrics.
 * CPU utilization is derived from deltas between /proc/stat samples; the first
 * request intentionally reports "sampling" rather than guessing a percentage.
 */
internal class SystemTelemetryReader(private val context: Context) {
    private data class CpuSample(val totalTicks: Long, val idleTicks: Long)
    private data class GpuInfo(
        val renderer: String?,
        val vendor: String?,
        val version: String?,
    )

    private var previousCpuSample: CpuSample? = null
    private val gpuInfo by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { readGpuInfo() }

    @Synchronized
    private fun cpuUsage(): Pair<Double?, String> {
        val current = readCpuSample() ?: return null to "unavailable"
        val previous = previousCpuSample
        previousCpuSample = current
        if (previous == null) return null to "sampling"

        val usage = calculateCpuUsagePercent(
            previous.totalTicks, previous.idleTicks,
            current.totalTicks, current.idleTicks,
        ) ?: return null to "sampling"
        return usage to "available"
    }

    private fun readCpuSample(): CpuSample? = runCatching {
        val line = File("/proc/stat").bufferedReader().use { it.readLine() }
            ?: return@runCatching null
        val fields = line.trim().split(Regex("\\s+"))
        if (fields.firstOrNull() != "cpu") return@runCatching null
        val ticks = fields.drop(1).mapNotNull { it.toLongOrNull() }
        if (ticks.size < 4) return@runCatching null
        CpuSample(
            totalTicks = ticks.sum(),
            idleTicks = ticks[3] + (ticks.getOrNull(4) ?: 0L),
        )
    }.getOrNull()

    fun snapshot(): JSONObject {
        val (cpuPercent, cpuStatus) = cpuUsage()
        val memory = readMemory()
        val storage = readStorage()
        val battery = readBattery()
        val gpu = gpuInfo

        val cpuModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL.takeIf { it.isNotBlank() }
        } else null

        return JSONObject()
            .put("sampled_at_ms", System.currentTimeMillis())
            .put("device", JSONObject()
                .put("manufacturer", Build.MANUFACTURER)
                .put("model", Build.MODEL)
                .put("device", Build.DEVICE)
                .put("android_version", Build.VERSION.RELEASE)
                .put("sdk", Build.VERSION.SDK_INT))
            .put("cpu", JSONObject()
                .put("model", cpuModel ?: Build.HARDWARE.takeIf { it.isNotBlank() } ?: JSONObject.NULL)
                .put("cores", Runtime.getRuntime().availableProcessors())
                .put("usage_percent", cpuPercent ?: JSONObject.NULL)
                .put("usage_status", cpuStatus))
            .put("memory", JSONObject()
                .put("total_bytes", memory?.first ?: JSONObject.NULL)
                .put("used_bytes", memory?.second ?: JSONObject.NULL)
                .put("available_bytes", memory?.third ?: JSONObject.NULL)
                .put("usage_percent", memory?.fourth ?: JSONObject.NULL))
            .put("storage", JSONObject()
                .put("total_bytes", storage?.first ?: JSONObject.NULL)
                .put("used_bytes", storage?.second ?: JSONObject.NULL)
                .put("available_bytes", storage?.third ?: JSONObject.NULL)
                .put("usage_percent", storage?.fourth ?: JSONObject.NULL))
            .put("gpu", JSONObject()
                .put("renderer", gpu.renderer ?: JSONObject.NULL)
                .put("vendor", gpu.vendor ?: JSONObject.NULL)
                .put("version", gpu.version ?: JSONObject.NULL))
            .put("battery", JSONObject()
                .put("percent", battery.first ?: JSONObject.NULL)
                .put("status", battery.second))
    }

    private fun readMemory(): Quadruple<Long, Long, Long, Double>? = runCatching {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo().also { manager.getMemoryInfo(it) }
        val total = info.totalMem.takeIf { it > 0L } ?: return@runCatching null
        val available = info.availMem.coerceIn(0L, total)
        val used = total - available
        Quadruple(total, used, available, used.toDouble() * 100.0 / total)
    }.getOrNull()

    private fun readStorage(): Quadruple<Long, Long, Long, Double>? = runCatching {
        val stats = StatFs(Environment.getExternalStorageDirectory().absolutePath)
        val total = stats.totalBytes.takeIf { it > 0L } ?: return@runCatching null
        val available = stats.availableBytes.coerceIn(0L, total)
        val used = total - available
        Quadruple(total, used, available, used.toDouble() * 100.0 / total)
    }.getOrNull()

    private fun readBattery(): Pair<Int?, String> {
        val intent = try {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        } catch (_: Exception) {
            null
        } ?: return null to "unknown"

        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val percent = if (level >= 0 && scale > 0) {
            (level * 100.0 / scale).toInt().coerceIn(0, 100)
        } else null
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val state = when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_DISCHARGING,
            BatteryManager.BATTERY_STATUS_NOT_CHARGING,
            BatteryManager.BATTERY_STATUS_FULL -> "not_charging"
            else -> "unknown"
        }
        return percent to state
    }

    private fun readGpuInfo(): GpuInfo {
        var display: EGLDisplay? = null
        var surface: EGLSurface? = null
        var eglContext: EGLContext? = null
        var initialized = false
        try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) return GpuInfo(null, null, null)

            val versions = IntArray(2)
            if (!EGL14.eglInitialize(display, versions, 0, versions, 1)) {
                return GpuInfo(null, null, null)
            }
            initialized = true

            val configs = arrayOfNulls<EGLConfig>(1)
            val configCount = IntArray(1)
            val configAttributes = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_NONE,
            )
            if (!EGL14.eglChooseConfig(
                    display, configAttributes, 0, configs, 0, 1, configCount, 0
                ) || configCount[0] == 0
            ) return GpuInfo(null, null, null)

            val config = configs[0] ?: return GpuInfo(null, null, null)
            surface = EGL14.eglCreatePbufferSurface(
                display, config,
                intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0,
            )
            if (surface == EGL14.EGL_NO_SURFACE) return GpuInfo(null, null, null)

            eglContext = EGL14.eglCreateContext(
                display, config, EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
            )
            if (eglContext == EGL14.EGL_NO_CONTEXT ||
                !EGL14.eglMakeCurrent(display, surface, surface, eglContext)
            ) return GpuInfo(null, null, null)

            return GpuInfo(
                renderer = GLES20.glGetString(GLES20.GL_RENDERER)?.trim()?.takeIf { it.isNotEmpty() },
                vendor = GLES20.glGetString(GLES20.GL_VENDOR)?.trim()?.takeIf { it.isNotEmpty() },
                version = GLES20.glGetString(GLES20.GL_VERSION)?.trim()?.takeIf { it.isNotEmpty() },
            )
        } catch (_: Exception) {
            return GpuInfo(null, null, null)
        } finally {
            val activeDisplay = display
            if (activeDisplay != null && activeDisplay != EGL14.EGL_NO_DISPLAY) {
                runCatching {
                    EGL14.eglMakeCurrent(
                        activeDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                        EGL14.EGL_NO_CONTEXT,
                    )
                }
                val activeContext = eglContext
                if (activeContext != null && activeContext != EGL14.EGL_NO_CONTEXT) {
                    runCatching { EGL14.eglDestroyContext(activeDisplay, activeContext) }
                }
                val activeSurface = surface
                if (activeSurface != null && activeSurface != EGL14.EGL_NO_SURFACE) {
                    runCatching { EGL14.eglDestroySurface(activeDisplay, activeSurface) }
                }
                if (initialized) runCatching { EGL14.eglTerminate(activeDisplay) }
            }
        }
    }

    private data class Quadruple<A, B, C, D>(
        val first: A,
        val second: B,
        val third: C,
        val fourth: D,
    )
}


internal fun calculateCpuUsagePercent(
    previousTotalTicks: Long,
    previousIdleTicks: Long,
    currentTotalTicks: Long,
    currentIdleTicks: Long,
): Double? {
    val totalDelta = currentTotalTicks - previousTotalTicks
    val idleDelta = currentIdleTicks - previousIdleTicks
    if (totalDelta <= 0L || idleDelta < 0L || idleDelta > totalDelta) return null
    return ((totalDelta - idleDelta).toDouble() * 100.0 / totalDelta)
        .coerceIn(0.0, 100.0)
}
