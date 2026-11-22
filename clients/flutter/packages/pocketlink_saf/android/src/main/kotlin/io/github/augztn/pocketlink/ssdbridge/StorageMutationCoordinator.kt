package io.github.augztn.pocketlink.ssdbridge

/** Serializes filesystem mutations performed by either native HTTP listener. */
internal object StorageMutationCoordinator {
    val lock = Any()
}
