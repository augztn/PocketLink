package dev.homeserver.ssdbridge

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import fi.iki.elonen.NanoHTTPD
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetSocketAddress
import java.net.Socket
import android.util.Base64

@RunWith(AndroidJUnit4::class)
class NativeApiServerIntegrationTest {
    @Test
    fun healthIsReachableAndApiRequiresValidCredentials() {
        val appContext = ApplicationProvider.getApplicationContext<Context>()
        // Keep test credentials isolated from the app's real saved server password.
        val context = object : ContextWrapper(appContext) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                appContext.getSharedPreferences("integration-test-$name", mode)
        }
        val credentials = ServerCredentials(context)
        val password = "integration-test-password"
        credentials.setPassword(password)
        // Let the OS allocate the port atomically when NanoHTTPD binds. Reserving
        // and then releasing a ServerSocket port creates a race with other processes.
        val server = NativeApiServer(context, credentials, 0, "0.0.0.0")

        server.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
        try {
            val port = server.listeningPort
            assertTrue("Native API server did not bind an ephemeral port", port > 0)
            val health = request(port, "/health")
            assertEquals(200, health.first)
            assertTrue(health.second.contains("\"status\":\"ok\""))

            val unauthenticated = request(port, "/api/storage/volumes")
            assertEquals(401, unauthenticated.first)

            val wrongPassword = request(
                port,
                "/api/storage/volumes",
                "Basic " + Base64.encodeToString("admin:incorrect-password".toByteArray(), Base64.NO_WRAP)
            )
            assertEquals(401, wrongPassword.first)

            val authorized = request(
                port,
                "/api/storage/volumes",
                "Basic " + Base64.encodeToString("admin:$password".toByteArray(), Base64.NO_WRAP)
            )
            assertEquals(200, authorized.first)
            assertTrue(authorized.second.contains("\"items\""))
        } finally {
            server.stop()
            context.getSharedPreferences("integration-test-homeserver-auth", Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    private fun request(port: Int, path: String, authorization: String? = null): Pair<Int, String> {
        Socket().use { socket ->
            socket.connect(InetSocketAddress("127.0.0.1", port), 5_000)
            socket.soTimeout = 15_000
            val headers = buildString {
                append("GET $path HTTP/1.1\\r\\n")
                append("Host: 127.0.0.1:$port\\r\\n")
                append("Connection: close\\r\\n")
                if (authorization != null) append("Authorization: $authorization\\r\\n")
                append("\\r\\n")
            }
            socket.getOutputStream().write(headers.toByteArray(Charsets.US_ASCII))
            socket.getOutputStream().flush()

            val input = socket.getInputStream().buffered()
            fun readHttpLine(): String {
                val bytes = ArrayList<Byte>()
                while (true) {
                    val value = input.read()
                    if (value == -1 || value == 10) break
                    if (value != 13) bytes.add(value.toByte())
                }
                return bytes.toByteArray().toString(Charsets.US_ASCII)
            }

            val statusLine = readHttpLine()
            val status = statusLine.split(" ").getOrNull(1)?.toIntOrNull()
                ?: error("Invalid HTTP response from native server: $statusLine")
            var contentLength = 0
            while (true) {
                val header = readHttpLine()
                if (header.isEmpty()) break
                if (header.startsWith("Content-Length:", ignoreCase = true)) {
                    contentLength = header.substringAfter(":").trim().toIntOrNull() ?: 0
                }
            }
            val body = ByteArray(contentLength)
            var offset = 0
            while (offset < body.size) {
                val count = input.read(body, offset, body.size - offset)
                if (count < 0) error("Native server closed before sending the full response body")
                offset += count
            }
            status to body.toString(Charsets.UTF_8)
        }
    }
}
