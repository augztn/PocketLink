package io.github.augztn.pocketlink.ssdbridge

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SafVolumeAccessStateTest {
    @Test
    fun reportsWritableOnlyWhenPersistedWriteGrantAndDocumentAllowIt() {
        val access = safVolumeAccessState(
            hasStoredUri = true,
            hasPersistedGrant = true,
            hasReadPermission = true,
            hasWritePermission = true,
            documentExists = true,
            documentCanRead = true,
            documentCanWrite = true
        )

        assertTrue(access.selected)
        assertTrue(access.readable)
        assertTrue(access.writable)
    }

    @Test
    fun readOnlyGrantNeverReportsWritable() {
        val access = safVolumeAccessState(
            hasStoredUri = true,
            hasPersistedGrant = true,
            hasReadPermission = true,
            hasWritePermission = false,
            documentExists = true,
            documentCanRead = true,
            documentCanWrite = true
        )

        assertTrue(access.selected)
        assertTrue(access.readable)
        assertFalse(access.writable)
    }

    @Test
    fun revokedGrantDoesNotReportReadableOrWritable() {
        val access = safVolumeAccessState(
            hasStoredUri = true,
            hasPersistedGrant = false,
            hasReadPermission = false,
            hasWritePermission = false,
            documentExists = false,
            documentCanRead = false,
            documentCanWrite = false
        )

        assertFalse(access.selected)
        assertFalse(access.readable)
        assertFalse(access.writable)
    }

    @Test
    fun unavailableDocumentDoesNotReportAccessEvenWithPersistedGrant() {
        val access = safVolumeAccessState(
            hasStoredUri = true,
            hasPersistedGrant = true,
            hasReadPermission = true,
            hasWritePermission = true,
            documentExists = false,
            documentCanRead = true,
            documentCanWrite = true
        )

        assertFalse(access.readable)
        assertFalse(access.writable)
    }

    @Test
    fun missingStoredUriIsNeverSelectedOrAccessible() {
        val access = safVolumeAccessState(
            hasStoredUri = false,
            hasPersistedGrant = true,
            hasReadPermission = true,
            hasWritePermission = true,
            documentExists = true,
            documentCanRead = true,
            documentCanWrite = true
        )

        assertFalse(access.selected)
        assertFalse(access.readable)
        assertFalse(access.writable)
    }
}
