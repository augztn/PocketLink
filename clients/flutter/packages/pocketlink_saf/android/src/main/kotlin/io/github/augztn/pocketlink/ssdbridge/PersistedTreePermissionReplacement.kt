package io.github.augztn.pocketlink.ssdbridge

internal enum class SelectionSaveResult {
    SAVED,
    FAILED_ROLLED_BACK,
    FAILED_STATE_UNCERTAIN
}

/**
 * Replaces one volume's persisted tree grant without invalidating grants still
 * referenced by another volume preference.
 */
internal object PersistedTreePermissionReplacement {
    fun replace(
        previousUri: String?,
        selectedUri: String,
        otherReferencedUris: Set<String>,
        takeSelectedPermission: () -> Unit,
        saveSelection: () -> SelectionSaveResult,
        releasePermission: (String) -> Unit
    ): Boolean {
        takeSelectedPermission()

        when (saveSelection()) {
            SelectionSaveResult.SAVED -> {
                if (previousUri != null &&
                    previousUri != selectedUri &&
                    previousUri !in otherReferencedUris
                ) {
                    releasePermission(previousUri)
                }
                return true
            }
            SelectionSaveResult.FAILED_ROLLED_BACK -> {
                if (selectedUri != previousUri && selectedUri !in otherReferencedUris) {
                    releasePermission(selectedUri)
                }
                return false
            }
            SelectionSaveResult.FAILED_STATE_UNCERTAIN -> {
                // Keep the new grant: preferences may still point to it in memory or on disk.
                return false
            }
        }
    }
}
