package io.github.augztn.pocketlink.ssdbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PersistedTreePermissionReplacementTest {
    @Test fun replacementSavesNewGrantBeforeReleasingUnreferencedOldGrant() {
        val events = mutableListOf<String>()

        val saved = PersistedTreePermissionReplacement.replace(
            previousUri = "content://old/tree",
            selectedUri = "content://new/tree",
            otherReferencedUris = emptySet(),
            takeSelectedPermission = { events += "take-new" },
            saveSelection = { events += "save-new"; true },
            releasePermission = { events += "release-$it" }
        )

        assertTrue(saved)
        assertEquals(
            listOf("take-new", "save-new", "release-content://old/tree"),
            events
        )
    }

    @Test fun selectingSameTreeDoesNotReleaseItsGrant() {
        val released = mutableListOf<String>()

        val saved = PersistedTreePermissionReplacement.replace(
            previousUri = "content://same/tree",
            selectedUri = "content://same/tree",
            otherReferencedUris = emptySet(),
            takeSelectedPermission = {},
            saveSelection = { true },
            releasePermission = { released += it }
        )

        assertTrue(saved)
        assertTrue(released.isEmpty())
    }

    @Test fun oldGrantStillReferencedByAnotherVolumeIsPreserved() {
        val released = mutableListOf<String>()

        PersistedTreePermissionReplacement.replace(
            previousUri = "content://shared/tree",
            selectedUri = "content://replacement/tree",
            otherReferencedUris = setOf("content://shared/tree"),
            takeSelectedPermission = {},
            saveSelection = { true },
            releasePermission = { released += it }
        )

        assertTrue(released.isEmpty())
    }

    @Test fun failedPreferenceSavePreservesOldGrantAndReleasesUnreferencedNewGrant() {
        val released = mutableListOf<String>()

        val saved = PersistedTreePermissionReplacement.replace(
            previousUri = "content://old/tree",
            selectedUri = "content://new/tree",
            otherReferencedUris = emptySet(),
            takeSelectedPermission = {},
            saveSelection = { false },
            releasePermission = { released += it }
        )

        assertFalse(saved)
        assertEquals(listOf("content://new/tree"), released)
    }

    @Test fun failedSaveDoesNotReleaseNewGrantReferencedByAnotherVolume() {
        val released = mutableListOf<String>()

        val saved = PersistedTreePermissionReplacement.replace(
            previousUri = "content://old/tree",
            selectedUri = "content://shared-new/tree",
            otherReferencedUris = setOf("content://shared-new/tree"),
            takeSelectedPermission = {},
            saveSelection = { false },
            releasePermission = { released += it }
        )

        assertFalse(saved)
        assertTrue(released.isEmpty())
    }

    @Test fun failedGrantAcquisitionDoesNotSaveOrReleaseAnything() {
        var saved = false
        val released = mutableListOf<String>()

        try {
            PersistedTreePermissionReplacement.replace(
                previousUri = "content://old/tree",
                selectedUri = "content://new/tree",
                otherReferencedUris = emptySet(),
                takeSelectedPermission = { throw SecurityException("grant denied") },
                saveSelection = { saved = true; true },
                releasePermission = { released += it }
            )
        } catch (_: SecurityException) {
            // The picker grant failed; the old preference and grant remain intact.
        }

        assertFalse(saved)
        assertTrue(released.isEmpty())
    }
}
