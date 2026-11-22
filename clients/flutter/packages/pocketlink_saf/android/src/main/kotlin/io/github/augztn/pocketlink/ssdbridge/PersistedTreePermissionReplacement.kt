package io.github.augztn.pocketlink.ssdbridge

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
        saveSelection: () -> Boolean,
        releasePermission: (String) -> Unit
    ): Boolean {
        takeSelectedPermission()

        if (!saveSelection()) {
            if (selectedUri != previousUri && selectedUri !in otherReferencedUris) {
                releasePermission(selectedUri)
            }
            return false
        }

        if (previousUri != null &&
            previousUri != selectedUri &&
            previousUri !in otherReferencedUris
        ) {
            releasePermission(previousUri)
        }
        return true
    }
}
