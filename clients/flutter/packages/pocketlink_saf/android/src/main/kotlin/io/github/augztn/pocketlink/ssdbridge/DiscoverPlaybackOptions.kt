package io.github.augztn.pocketlink.ssdbridge

internal object DiscoverPlaybackOptions {
    const val BEST_AVAILABLE = "best_available"
    const val BALANCED = "balanced"
    const val DATA_SAVER = "data_saver"

    const val AUTOMATIC = "automatic"
    const val NEWPIPE_FIRST = "newpipe_first"
    const val PLAYER_API_FIRST = "player_api_first"

    private const val BALANCED_TARGET_BPS = 160_000L
    private const val DATA_SAVER_TARGET_BPS = 96_000L

    fun normalizeQuality(value: String?): String = when (value?.lowercase()) {
        BALANCED -> BALANCED
        DATA_SAVER -> DATA_SAVER
        else -> BEST_AVAILABLE
    }

    fun normalizeResolverProfile(value: String?): String = when (value?.lowercase()) {
        NEWPIPE_FIRST -> NEWPIPE_FIRST
        PLAYER_API_FIRST -> PLAYER_API_FIRST
        else -> AUTOMATIC
    }

    fun normalizeRegion(value: String?): String {
        val normalized = value?.trim()?.uppercase()
        return normalized?.takeIf { REGION_PATTERN.matches(it) } ?: "IN"
    }

    fun resolverOrder(profile: String?, lastSuccessfulResolver: String?): List<String> =
        when (normalizeResolverProfile(profile)) {
            NEWPIPE_FIRST -> listOf("NEWPIPE", "PLAYER_API")
            PLAYER_API_FIRST -> listOf("PLAYER_API", "NEWPIPE")
            else -> if (lastSuccessfulResolver == "PLAYER_API") {
                listOf("PLAYER_API", "NEWPIPE")
            } else {
                listOf("NEWPIPE", "PLAYER_API")
            }
        }

    fun <T> selectAudioFormat(
        formats: List<T>,
        quality: String?,
        bitrateBps: (T) -> Long,
        isOpus: (T) -> Boolean
    ): T? {
        if (formats.isEmpty()) return null
        val normalizedQuality = normalizeQuality(quality)
        if (normalizedQuality == BEST_AVAILABLE) {
            return formats.maxWithOrNull(
                compareBy<T> { isOpus(it) }.thenBy { bitrateBps(it) }
            )
        }

        val knownBitrates = formats.filter { bitrateBps(it) > 0L }
        if (knownBitrates.isEmpty()) {
            return formats.maxWithOrNull(compareBy<T> { isOpus(it) })
        }
        val target = if (normalizedQuality == DATA_SAVER) {
            DATA_SAVER_TARGET_BPS
        } else {
            BALANCED_TARGET_BPS
        }
        val withinTarget = knownBitrates.filter { bitrateBps(it) <= target }
        return if (withinTarget.isNotEmpty()) {
            withinTarget.maxWithOrNull(
                compareBy<T> { bitrateBps(it) }.thenBy { isOpus(it) }
            )
        } else {
            knownBitrates.minWithOrNull(
                compareBy<T> { bitrateBps(it) }.thenByDescending { isOpus(it) }
            )
        }
    }

    fun qualityFallbackReason(quality: String?, bitrateBps: Long): String? {
        val normalizedQuality = normalizeQuality(quality)
        if (normalizedQuality == BEST_AVAILABLE) return null
        if (bitrateBps <= 0L) {
            return "The selected stream did not report a bitrate."
        }
        val target = if (normalizedQuality == DATA_SAVER) {
            DATA_SAVER_TARGET_BPS
        } else {
            BALANCED_TARGET_BPS
        }
        return if (bitrateBps > target) {
            "No available stream met the requested bitrate target; the closest available stream was selected."
        } else {
            null
        }
    }

    private val REGION_PATTERN = Regex("[A-Z]{2}")
}
