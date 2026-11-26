package io.github.augztn.pocketlink.ssdbridge

internal data class SafVolumeAccessState(
    val selected: Boolean,
    val readable: Boolean,
    val writable: Boolean
)

/**
 * Reports only access that is backed by a persisted Android grant and a
 * currently available document tree. A stored URI alone is not permission.
 */
internal fun safVolumeAccessState(
    hasStoredUri: Boolean,
    hasPersistedGrant: Boolean,
    hasReadPermission: Boolean,
    hasWritePermission: Boolean,
    documentExists: Boolean,
    documentCanRead: Boolean,
    documentCanWrite: Boolean
): SafVolumeAccessState {
    val readable = hasStoredUri &&
        hasPersistedGrant &&
        hasReadPermission &&
        documentExists &&
        documentCanRead
    return SafVolumeAccessState(
        selected = readable,
        readable = readable,
        writable = readable && hasWritePermission && documentCanWrite
    )
}
