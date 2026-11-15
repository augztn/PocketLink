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
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.URL
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
        val port = ServerSocket(0).use { it.localPort }
        val server = NativeApiServer(context, credentials, port)

        server.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
        try {
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
        val connection = URL("http://127.0.0.1:$port$path").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 5_000
            connection.readTimeout = 5_000
            if (authorization != null) connection.setRequestProperty("Authorization", authorization)
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            status to body
        } finally {
            connection.disconnect()
        }
    }
}
