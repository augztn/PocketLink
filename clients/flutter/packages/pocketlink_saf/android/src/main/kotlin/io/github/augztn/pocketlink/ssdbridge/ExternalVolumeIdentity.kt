package io.github.augztn.pocketlink.ssdbridge

/** Deterministic identity independent of the current volume enumeration index. */
internal fun externalVolumeIdentity(uuid: String?, directoryPath: String?, description: String): String {
    uuid?.trim()?.takeIf { it.isNotEmpty() }?.let { return "uuid:${it.lowercase()}" }
    directoryPath?.trim()?.takeIf { it.isNotEmpty() }?.let { return "path:$it" }
    return "description:${description.trim().lowercase()}"
}
