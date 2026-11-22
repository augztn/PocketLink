package io.github.augztn.pocketlink.ssdbridge

import android.util.Base64

/**
 * Validates the HTTP Basic credential envelope before delegating password
 * verification to the salted credential store.
 */
internal class NativeApiAuthentication(
    private val username: String,
    private val verifyPassword: (CharArray) -> Boolean,
    private val decodeBase64: (String) -> ByteArray = { Base64.decode(it, Base64.DEFAULT) }
) {
    fun isAuthorized(headers: Map<String, String>): Boolean {
        val header = headers["authorization"] ?: return false
        if (!header.startsWith("Basic ", ignoreCase = true)) return false

        val decoded = try {
            val encoded = header.substringAfter(' ').trim()
                .filterNot { it.isWhitespace() }
            String(decodeBase64(encoded), Charsets.UTF_8)
        } catch (_: IllegalArgumentException) {
            return false
        }

        val separator = decoded.indexOf(':')
        if (separator <= 0 || decoded.substring(0, separator) != username) return false
        return verifyPassword(decoded.substring(separator + 1).toCharArray())
    }
}
