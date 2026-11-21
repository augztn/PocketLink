package io.github.augztn.pocketlink.ssdbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.UUID

class InternalStorageAccessTest {
    @Test
    fun resolvesNestedPathsAndRejectsTraversalAndHiddenSegments() {
        val root = File(System.getProperty("java.io.tmpdir"), "internal-storage-${UUID.randomUUID()}")
        val nested = File(root, "Documents").apply { check(mkdirs()) }
        val file = File(nested, "notes.txt").apply { writeText("safe") }
        val access = InternalStorageAccess(root, ::isValidName)

        try {
            assertEquals(root.canonicalFile, access.resolve(""))
            assertEquals(file.canonicalFile, access.resolve("Documents/notes.txt"))
            assertNull(access.resolve("../outside.txt"))
            assertNull(access.resolve("Documents/../outside.txt"))
            assertNull(access.resolve(".hidden"))
            assertNull(access.resolve("Documents/.hidden"))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun rejectsSymlinkThatEscapesStorageRoot() {
        val parent = File(System.getProperty("java.io.tmpdir"), "internal-storage-link-${UUID.randomUUID()}")
        val root = File(parent, "root").apply { check(mkdirs()) }
        val outside = File(parent, "outside").apply { check(mkdirs()) }
        File(outside, "secret.txt").writeText("private")
        val link = File(root, "escape")
        val access = InternalStorageAccess(root, ::isValidName)

        try {
            Files.createSymbolicLink(link.toPath(), outside.toPath())
            assertNull(access.resolve("escape/secret.txt"))
        } finally {
            parent.deleteRecursively()
        }
    }

    private fun isValidName(value: String): Boolean =
        value.isNotBlank() && value != "." && value != ".." &&
            !value.startsWith(".") && !value.contains('/') && !value.contains('\\') &&
            !value.any { it.code < 32 }
}
