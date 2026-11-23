package io.github.augztn.pocketlink.ssdbridge

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class NativeDiagnosticsTest {
    @Test
    fun writesStructuredEventsAndPreservesTypedFields() {
        val directory = Files.createTempDirectory("pocketlink-native-diagnostics").toFile()
        try {
            val log = File(directory, "native.log")
            NativeDiagnostics.initializeForTesting(log)

            NativeDiagnostics.record(
                level = "INFO",
                category = "service",
                component = "bridge_service",
                message = "Native service started",
                fields = mapOf("port" to 8000, "running" to true, "duration_ms" to 12.5)
            )

            val event = JSONObject(log.readLines().single())
            assertEquals("INFO", event.getString("level"))
            assertEquals("service", event.getString("category"))
            assertEquals(8000, event.getJSONObject("fields").getInt("port"))
            assertTrue(event.getJSONObject("fields").getBoolean("running"))
            assertEquals(12.5, event.getJSONObject("fields").getDouble("duration_ms"), 0.0)
            assertTrue(event.getString("event_id").contains(event.getString("session_id")))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun redactsSecretsHostsAndPrivatePathsBeforePersistence() {
        val directory = Files.createTempDirectory("pocketlink-native-privacy").toFile()
        try {
            val log = File(directory, "native.log")
            NativeDiagnostics.initializeForTesting(log)

            NativeDiagnostics.record(
                level = "ERROR",
                category = "storage",
                component = "saf",
                message = "Failed at /sdcard/Documents/private.pdf via https://private.example:8000/api/files",
                fields = mapOf(
                    "accessToken" to "secret-value",
                    "filePath" to "/storage/emulated/0/private.txt",
                    "status_code" to 403
                )
            )

            val raw = log.readText()
            assertFalse(raw.contains("secret-value"))
            assertFalse(raw.contains("private.example"))
            assertFalse(raw.contains("/sdcard/Documents"))
            assertFalse(raw.contains("/storage/emulated"))
            assertTrue(raw.contains("[REDACTED]"))
            assertTrue(raw.contains("[REDACTED_PATH]"))
            assertTrue(raw.contains("/api/files"))
            assertTrue(raw.contains("403"))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun preservesApiRoutesAndOperationalFieldsWhileRedactingPrivatePaths() {
        val directory = Files.createTempDirectory("pocketlink-native-route-privacy").toFile()
        try {
            val log = File(directory, "native.log")
            NativeDiagnostics.initializeForTesting(log)
            NativeDiagnostics.record(
                level = "INFO",
                category = "network",
                component = "server_api",
                message = "Request completed",
                fields = mapOf(
                    "path" to "/api/files/",
                    "hostMode" to "tailscale",
                    "serverStatus" to "online",
                    "filePath" to "/sdcard/private.txt",
                    "username" to "admin"
                )
            )
            val fields = JSONObject(log.readLines().single()).getJSONObject("fields")
            assertEquals("/api/files/", fields.getString("path"))
            assertEquals("tailscale", fields.getString("hostMode"))
            assertEquals("online", fields.getString("serverStatus"))
            assertEquals("[REDACTED_PATH]", fields.getString("filePath"))
            assertEquals("[REDACTED]", fields.getString("username"))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun rotatesNativeJournalWithoutExceedingBackupLimit() {
        val directory = Files.createTempDirectory("pocketlink-native-rotation").toFile()
        try {
            val log = File(directory, "native.log")
            NativeDiagnostics.initializeForTesting(log)
            log.writeText("x".repeat(600 * 1024))

            NativeDiagnostics.record(
                level = "INFO",
                category = "service",
                component = "bridge_service",
                message = "Rotation checkpoint"
            )

            assertTrue(File(log.path + ".1").length() <= 512L * 1024L)
            assertTrue(log.length() < 1024L)
        } finally {
            directory.deleteRecursively()
        }
    }
}
