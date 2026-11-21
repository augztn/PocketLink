package io.github.augztn.pocketlink.ssdbridge

import java.io.File

/**
 * Resolves paths within PocketLink's internal shared-storage root.
 * Canonical-path containment is checked after resolving symlinks.
 */
internal class InternalStorageAccess(
    root: File,
    private val isValidName: (String) -> Boolean
) {
    private val canonicalRoot = root.canonicalFile

    fun resolve(relative: String): File? {
        if (relative.isBlank()) return canonicalRoot
        if (relative.split('/').any { !isValidName(it) }) return null

        val target = File(canonicalRoot, relative).canonicalFile
        val rootPrefix = canonicalRoot.path + File.separator
        return target.takeIf {
            it.path == canonicalRoot.path || it.path.startsWith(rootPrefix)
        }
    }
}
