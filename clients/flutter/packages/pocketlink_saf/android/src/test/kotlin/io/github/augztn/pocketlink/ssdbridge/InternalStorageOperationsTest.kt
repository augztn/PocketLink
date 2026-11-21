package io.github.augztn.pocketlink.ssdbridge

import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

class InternalStorageOperationsTest {
    @Test
    fun listsVisibleItemsWithDirectoriesFirstAndStableNameOrdering() {
        val root = temporaryRoot()
        try {
            File(root, "z-file.txt").writeText("file")
            File(root, "Alpha").mkdir()
            File(root, "beta").mkdir()
            File(root, ".hidden").writeText("hidden")

            val response = operations(root).list("")
            assertEquals(NanoHTTPD.Response.Status.OK, response.status)
            val body = response.data.bufferedReader().use { it.readText() }
            val items = JSONObject(body).getJSONArray("items")
            assertEquals(3, items.length())
            assertEquals("Alpha", items.getJSONObject(0).getString("name"))
            assertEquals("beta", items.getJSONObject(1).getString("name"))
            assertEquals("z-file.txt", items.getJSONObject(2).getString("name"))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun refusesDeletingRootOrNonEmptyDirectoriesAndDeletesFiles() {
        val root = temporaryRoot()
        try {
            val folder = File(root, "folder").apply { mkdir() }
            val nested = File(folder, "nested.txt").apply { writeText("keep") }
            val file = File(root, "remove.txt").apply { writeText("remove") }
            val operations = operations(root)

            assertEquals(NanoHTTPD.Response.Status.BAD_REQUEST, operations.delete("").status)
            assertEquals(NanoHTTPD.Response.Status.BAD_REQUEST, operations.delete("folder").status)
            assertTrue(nested.exists())
            assertEquals(NanoHTTPD.Response.Status.OK, operations.delete("remove.txt").status)
            assertFalse(file.exists())
        } finally {
            root.deleteRecursively()
        }
    }

    private fun operations(root: File) = InternalStorageOperations(
        root = { root.canonicalFile },
        resolve = { relative ->
            if (relative.isBlank()) root.canonicalFile
            else File(root, relative).canonicalFile.takeIf {
                it.path.startsWith(root.canonicalPath + File.separator) &&
                    relative.split('/').all(::isValidName)
            }
        },
        isValidName = ::isValidName,
        parseMultipart = { null },
        parseJsonBody = { null },
        fileJson = { file ->
            JSONObject().put("name", file.name)
                .put("type", if (file.isDirectory) "directory" else "file")
        },
        fileResponse = { _, _, _ -> error("Not used by this test") },
        json = { value ->
            NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK,
                "application/json",
                value.toString()
            )
        },
        error = { status, message ->
            NanoHTTPD.newFixedLengthResponse(
                status,
                "application/json",
                JSONObject().put("detail", message).toString()
            )
        },
        markMediaIndexDirty = {},
        mutationLock = Any()
    )

    private fun temporaryRoot() = File(
        System.getProperty("java.io.tmpdir"),
        "internal-storage-operations-${UUID.randomUUID()}"
    ).apply { check(mkdirs()) }

    private fun isValidName(value: String): Boolean =
        value.isNotBlank() && value != "." && value != ".." &&
            !value.startsWith(".") && !value.contains('/') && !value.contains('\\') &&
            !value.any { it.code < 32 }
}
