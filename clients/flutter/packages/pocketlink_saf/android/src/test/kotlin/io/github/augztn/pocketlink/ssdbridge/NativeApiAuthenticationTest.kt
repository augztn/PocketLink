package io.github.augztn.pocketlink.ssdbridge

import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeApiAuthenticationTest {
    @Test
    fun acceptsValidBasicCredentials() {
        var verifiedPassword: String? = null
        val authentication = authentication("admin") { password ->
            verifiedPassword = String(password)
            true
        }

        assertTrue(authentication.isAuthorized(header("admin:correct-horse")))
        assertEquals("correct-horse", verifiedPassword)
    }

    @Test
    fun rejectsMissingOrUnsupportedAuthorizationHeader() {
        val authentication = authentication("admin") { true }

        assertFalse(authentication.isAuthorized(emptyMap()))
        assertFalse(authentication.isAuthorized(mapOf("authorization" to "Bearer token")))
    }

    @Test
    fun rejectsMalformedBase64AndMissingUsernameSeparator() {
        val authentication = authentication("admin") { true }

        assertFalse(authentication.isAuthorized(mapOf("authorization" to "Basic !!!")))
        assertFalse(authentication.isAuthorized(header("admin")))
        assertFalse(authentication.isAuthorized(header(":password")))
    }

    @Test
    fun rejectsUnexpectedUsernameWithoutCheckingPassword() {
        var verificationCalled = false
        val authentication = authentication("admin") {
            verificationCalled = true
            true
        }

        assertFalse(authentication.isAuthorized(header("other:password")))
        assertFalse(verificationCalled)
    }

    @Test
    fun returnsPasswordVerifierResult() {
        val authentication = authentication("admin") { false }

        assertFalse(authentication.isAuthorized(header("admin:wrong-password")))
    }

    @Test
    fun acceptsCaseInsensitiveBasicSchemeAndHeaderWhitespace() {
        val authentication = authentication("admin") { String(it) == "password" }
        val encoded = Base64.getEncoder().encodeToString("admin:password".toByteArray(Charsets.UTF_8))

        assertTrue(authentication.isAuthorized(mapOf("authorization" to "basic   $encoded  ")))
    }

    private fun authentication(
        username: String,
        verifyPassword: (CharArray) -> Boolean
    ) = NativeApiAuthentication(username, verifyPassword) { encoded ->
        Base64.getDecoder().decode(encoded)
    }

    private fun header(value: String): Map<String, String> =
        mapOf(
            "authorization" to
                "Basic ${Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8))}"
        )
}
