package io.github.augztn.pocketlink.ssdbridge

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
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
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

        server.start(30_000, false)
        try {
            val port = server.listeningPort
            assertTrue("Native API server did not bind an ephemeral port", port > 0)
            val health = request(port, "/health")
            assertEquals(200, health.first)
            assertTrue(health.second.contains("\"status\":\"ok\""))

            val unauthenticated = request(port, "/api/storage/volumes")
            assertEquals(401, unauthenticated.first)

            val unauthenticatedIndex = request(port, "/api/index/status")
            assertEquals(401, unauthenticatedIndex.first)

            val unauthenticatedTelemetry = request(port, "/api/system/telemetry")
            assertEquals(401, unauthenticatedTelemetry.first)

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

            val telemetry = request(
                port,
                "/api/system/telemetry",
                "Basic " + Base64.encodeToString("admin:$password".toByteArray(), Base64.NO_WRAP)
            )
            assertEquals(200, telemetry.first)
            listOf("\"device\"", "\"cpu\"", "\"memory\"", "\"storage\"", "\"battery\"")
                .forEach { key -> assertTrue("Missing telemetry field $key", telemetry.second.contains(key)) }
            assertTrue("Unsupported GPU telemetry must not be advertised", !telemetry.second.contains("\"gpu\""))
        } finally {
            server.stop()
            context.getSharedPreferences("integration-test-pocketlink-auth", Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    @Test
    fun externalStorageAccessResolvesSafeDocumentPaths() {
        val appContext = ApplicationProvider.getApplicationContext<Context>()
        val root = File(appContext.cacheDir, "external-access-test-${UUID.randomUUID()}").apply {
            check(mkdirs())
        }
        val nested = File(root, "nested").apply { check(mkdir()) }
        File(nested, "inside.txt").writeText("safe")
        val preferences = appContext.getSharedPreferences(
            "external-access-test-${UUID.randomUUID()}", Context.MODE_PRIVATE
        )
        val access = ExternalStorageAccess(appContext, preferences) { name ->
            name.isNotBlank() && name != "." && name != ".." &&
                !name.startsWith(".") && !name.contains('/') && !name.contains('\\') &&
                !name.any { it.code < 32 }
        }

        try {
            val documentRoot = androidx.documentfile.provider.DocumentFile.fromFile(root)
            assertTrue(access.resolveDocument(documentRoot, "nested/inside.txt")?.isFile == true)
            assertTrue(access.resolveDocument(documentRoot, "../outside.txt") == null)
            assertTrue(access.resolveDocument(documentRoot, "nested/../inside.txt") == null)
            assertTrue(access.resolveDocument(documentRoot, ".hidden") == null)
        } finally {
            root.deleteRecursively()
            preferences.edit().clear().commit()
        }
    }

    @Test
    fun mediaIndexSettingsRoutesPreserveValidationAndConfigurationContract() {
        val appContext = ApplicationProvider.getApplicationContext<Context>()
        val context = object : ContextWrapper(appContext) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                appContext.getSharedPreferences("index-route-test-$name", mode)
        }
        val root = File(context.cacheDir, "index-route-test-${UUID.randomUUID()}").apply {
            check(mkdirs())
        }
        val credentials = ServerCredentials(context)
        val password = "index-route-test-password"
        credentials.setPassword(password)
        val authorization = "Basic " + Base64.encodeToString(
            "admin:$password".toByteArray(), Base64.NO_WRAP
        )
        val server = NativeApiServer(context, credentials, 0, "0.0.0.0", root)
        server.start(30_000, false)
        try {
            val port = server.listeningPort
            val settings = request(port, "/api/index/settings", authorization)
            assertEquals(200, settings.first)
            assertTrue(settings.second.contains("\"interval_minutes\""))

            val invalidInterval = request(
                port,
                "/api/index/settings?enabled=true&interval_minutes=10",
                authorization,
                method = "POST"
            )
            assertEquals(400, invalidInterval.first)
            assertTrue(invalidInterval.second.contains("15 and 1440"))

            val updated = request(
                port,
                "/api/index/settings?enabled=false&interval_minutes=60&scan_on_startup=false&scan_on_storage_change=false",
                authorization,
                method = "POST"
            )
            assertEquals(200, updated.first)
            assertTrue(updated.second.contains("\"enabled\":false"))
            assertTrue(updated.second.contains("\"interval_minutes\":60"))
            assertTrue(updated.second.contains("\"scan_on_startup\":false"))
            assertTrue(updated.second.contains("\"scan_on_storage_change\":false"))
        } finally {
            server.closeMediaIndex()
            server.stop()
            root.deleteRecursively()
            context.getSharedPreferences("index-route-test-ssd-bridge", Context.MODE_PRIVATE)
                .edit().clear().commit()
            context.getSharedPreferences("index-route-test-pocketlink-auth", Context.MODE_PRIVATE)
                .edit().clear().commit()
            context.getSharedPreferences("index-route-test-media-index-report", Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    @Test
    fun concurrentUploadsAndRenamesNeverReplaceAnExistingDestination() {
        val appContext = ApplicationProvider.getApplicationContext<Context>()
        val context = object : ContextWrapper(appContext) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                appContext.getSharedPreferences("mutation-test-$name", mode)
        }
        val root = File(context.cacheDir, "mutation-test-${UUID.randomUUID()}").apply {
            check(mkdirs())
        }
        val credentials = ServerCredentials(context)
        val password = "mutation-test-password"
        credentials.setPassword(password)
        val authorization = "Basic " + Base64.encodeToString(
            "admin:$password".toByteArray(), Base64.NO_WRAP
        )
        val server = NativeApiServer(context, credentials, 0, "0.0.0.0", root)
        val executor = Executors.newFixedThreadPool(12)

        server.start(30_000, false)
        try {
            val port = server.listeningPort
            File(root, "listed.txt").writeText("route-dispatch-check")
            val listing = request(port, "/api/files/", authorization)
            assertEquals(200, listing.first)
            assertTrue("Internal file listing route was not dispatched", listing.second.contains("listed.txt"))

            val protectedUpload = File(root, "protected.txt").apply { writeText("original-upload") }
            val rejectedUpload = request(
                port,
                "/api/files/upload?path=",
                authorization,
                method = "POST",
                body = multipartBody("protected.txt", "replacement".toByteArray()),
                contentType = "multipart/form-data; boundary=pocketlink-test-boundary"
            )
            assertEquals(409, rejectedUpload.first)
            assertEquals("original-upload", protectedUpload.readText())

            val payloads = (0 until 12).map { "upload-payload-$it".toByteArray() }
            val uploadGate = CountDownLatch(1)
            val uploadResponses = payloads.map { payload ->
                executor.submit<Pair<Int, String>> {
                    uploadGate.await()
                    request(
                        port,
                        "/api/files/upload?path=",
                        authorization,
                        method = "POST",
                        body = multipartBody("shared.txt", payload),
                        contentType = "multipart/form-data; boundary=pocketlink-test-boundary"
                    )
                }
            }
            uploadGate.countDown()
            val completedUploads = uploadResponses.map { it.get() }

            assertEquals(1, completedUploads.count { it.first == 200 })
            assertEquals(11, completedUploads.count { it.first == 409 })
            assertTrue(
                "The committed upload must match exactly one complete request body",
                payloads.any { it.contentEquals(File(root, "shared.txt").readBytes()) }
            )

            val occupied = File(root, "occupied.txt").apply { writeText("original-rename-target") }
            val blockedSource = File(root, "blocked-source.txt").apply { writeText("source-content") }
            val rejectedRename = request(
                port,
                "/api/files/rename",
                authorization,
                method = "PATCH",
                body = """{"path":"blocked-source.txt","new_name":"occupied.txt"}""".toByteArray(),
                contentType = "application/json"
            )
            assertEquals(409, rejectedRename.first)
            assertEquals("original-rename-target", occupied.readText())
            assertEquals("source-content", blockedSource.readText())

            val sourceContents = (0 until 12).associate { index ->
                "source-$index.txt" to "rename-source-$index".toByteArray()
            }
            sourceContents.forEach { (name, bytes) -> File(root, name).writeBytes(bytes) }
            val renameGate = CountDownLatch(1)
            val renameResponses = sourceContents.keys.map { source ->
                executor.submit<Pair<Int, String>> {
                    renameGate.await()
                    request(
                        port,
                        "/api/files/rename",
                        authorization,
                        method = "PATCH",
                        body = """{"path":"$source","new_name":"renamed.txt"}""".toByteArray(),
                        contentType = "application/json"
                    )
                }
            }
            renameGate.countDown()
            val completedRenames = renameResponses.map { it.get() }

            assertEquals(1, completedRenames.count { it.first == 200 })
            assertEquals(11, completedRenames.count { it.first == 409 })
            assertTrue(
                "The committed rename must preserve one complete source file",
                sourceContents.values.any { it.contentEquals(File(root, "renamed.txt").readBytes()) }
            )
            assertEquals(
                "All losing rename sources must remain untouched",
                11,
                sourceContents.keys.count { File(root, it).exists() }
            )
        } finally {
            executor.shutdownNow()
            server.stop()
            root.deleteRecursively()
            context.getSharedPreferences("mutation-test-ssd-bridge", Context.MODE_PRIVATE)
                .edit().clear().commit()
            context.getSharedPreferences("mutation-test-pocketlink-auth", Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    @Test
    fun concurrentDeletesSerializeAndResolveAfterEarlierMutations() {
        val appContext = ApplicationProvider.getApplicationContext<Context>()
        val context = object : ContextWrapper(appContext) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                appContext.getSharedPreferences("delete-mutation-test-$name", mode)
        }
        val root = File(context.cacheDir, "delete-mutation-test-${UUID.randomUUID()}").apply {
            check(mkdirs())
        }
        val target = File(root, "shared-delete.txt").apply { writeText("delete-once") }
        val credentials = ServerCredentials(context)
        val password = "delete-mutation-test-password"
        credentials.setPassword(password)
        val authorization = "Basic " + Base64.encodeToString(
            "admin:$password".toByteArray(), Base64.NO_WRAP
        )
        val server = NativeApiServer(context, credentials, 0, "0.0.0.0", root)
        val executor = Executors.newFixedThreadPool(12)
        server.start(30_000, false)
        try {
            val port = server.listeningPort
            val gate = CountDownLatch(1)
            val requests = (0 until 12).map {
                executor.submit<Pair<Int, String>> {
                    gate.await()
                    request(
                        port,
                        "/api/files/item?path=shared-delete.txt",
                        authorization,
                        method = "DELETE"
                    )
                }
            }
            gate.countDown()
            val responses = requests.map { it.get() }

            assertEquals("Exactly one request must delete the file", 1, responses.count { it.first == 200 })
            assertEquals("Later requests must fail after the first delete", 11, responses.count { it.first == 500 })
            assertTrue("The target must be deleted exactly once", !target.exists())
        } finally {
            executor.shutdownNow()
            server.stop()
            root.deleteRecursively()
            context.getSharedPreferences("delete-mutation-test-ssd-bridge", Context.MODE_PRIVATE)
                .edit().clear().commit()
            context.getSharedPreferences("delete-mutation-test-pocketlink-auth", Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    @Test
    fun fileStreamingReturnsFullAndRequestedByteRangeOverHttp() {
        val appContext = ApplicationProvider.getApplicationContext<Context>()
        val context = object : ContextWrapper(appContext) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                appContext.getSharedPreferences("stream-test-$name", mode)
        }
        val root = File(context.cacheDir, "stream-test-${UUID.randomUUID()}").apply {
            check(mkdirs())
        }
        val source = File(root, "sample.txt").apply { writeText("0123456789") }
        val credentials = ServerCredentials(context)
        val password = "stream-test-password"
        credentials.setPassword(password)
        val authorization = "Basic " + Base64.encodeToString(
            "admin:$password".toByteArray(), Base64.NO_WRAP
        )
        val server = NativeApiServer(context, credentials, 0, "0.0.0.0", root)

        server.start(30_000, false)
        try {
            val port = server.listeningPort
            val full = request(port, "/api/files/stream?path=sample.txt", authorization)
            assertEquals(200, full.first)
            assertEquals(source.readText(), full.second)

            val partial = request(
                port,
                "/api/files/stream?path=sample.txt",
                authorization,
                extraHeaders = mapOf("Range" to "bytes=2-5")
            )
            assertEquals(206, partial.first)
            assertEquals("2345", partial.second)
        } finally {
            server.stop()
            root.deleteRecursively()
            context.getSharedPreferences("stream-test-ssd-bridge", Context.MODE_PRIVATE)
                .edit().clear().commit()
            context.getSharedPreferences("stream-test-pocketlink-auth", Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    private fun multipartBody(name: String, content: ByteArray): ByteArray {
        val prefix = (
            "--pocketlink-test-boundary\r\n" +
                "Content-Disposition: form-data; name=\"file\"; filename=\"$name\"\r\n" +
                "Content-Type: application/octet-stream\r\n\r\n"
            ).toByteArray(Charsets.UTF_8)
        val suffix = "\r\n--pocketlink-test-boundary--\r\n".toByteArray(Charsets.UTF_8)
        return prefix + content + suffix
    }

    private fun request(
        port: Int,
        path: String,
        authorization: String? = null,
        method: String = "GET",
        body: ByteArray = byteArrayOf(),
        contentType: String? = null,
        extraHeaders: Map<String, String> = emptyMap()
    ): Pair<Int, String> {
        return Socket().use { socket ->
            socket.connect(InetSocketAddress("127.0.0.1", port), 5_000)
            socket.soTimeout = 45_000
            val headers = buildString {
                append("$method $path HTTP/1.1\r\n")
                append("Host: 127.0.0.1:$port\r\n")
                append("Connection: close\r\n")
                if (authorization != null) append("Authorization: $authorization\r\n")
                if (contentType != null) append("Content-Type: $contentType\r\n")
                extraHeaders.forEach { (name, value) -> append("$name: $value\r\n") }
                if (body.isNotEmpty()) append("Content-Length: ${body.size}\r\n")
                append("\r\n")
            }
            socket.getOutputStream().apply {
                write(headers.toByteArray(Charsets.US_ASCII))
                if (body.isNotEmpty()) write(body)
                flush()
            }

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
            val responseBody = ByteArray(contentLength)
            var offset = 0
            while (offset < responseBody.size) {
                val count = input.read(responseBody, offset, responseBody.size - offset)
                if (count < 0) error("Native server closed before sending the full response body")
                offset += count
            }
            status to responseBody.toString(Charsets.UTF_8)
        }
    }
}
