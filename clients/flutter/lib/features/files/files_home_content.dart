import 'package:material_ui/material_ui.dart';

import '../../core/network/server_api.dart';
import '../../core/storage/home_activity_store.dart';

/// Landing page for Files. Navigation and storage state remain owned by the
/// file manager so switching locations never creates a second browser stack.
class FilesHomeContent extends StatelessWidget {
  const FilesHomeContent({
    required this.volumes,
    required this.recent,
    required this.favorites,
    required this.lastPath,
    required this.lastVolume,
    required this.onOpenInternal,
    required this.onOpenVolume,
    required this.onOpenRecent,
    required this.onOpenFavorite,
    required this.onOpenLastLocation,
    required this.onBrowseCategory,
    super.key,
  });

  final List<StorageVolume> volumes;
  final List<HomeActivityItem> recent;
  final List<HomeActivityItem> favorites;
  final String lastPath;
  final String? lastVolume;
  final VoidCallback onOpenInternal;
  final ValueChanged<String> onOpenVolume;
  final ValueChanged<HomeActivityItem> onOpenRecent;
  final ValueChanged<HomeActivityItem> onOpenFavorite;
  final VoidCallback onOpenLastLocation;
  final ValueChanged<String> onBrowseCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locations = [
      _Location(
        title: 'Internal storage',
        subtitle: 'Browse phone storage',
        icon: Icons.phone_android_rounded,
        onTap: onOpenInternal,
      ),
      for (final volume in volumes)
        _Location(
          title: volume.name,
          subtitle: volume.writable ? 'External storage · Writable' : 'External storage',
          icon: Icons.usb_rounded,
          onTap: () => onOpenVolume(volume.id),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Text('Your files', style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -0.5,
        )),
        const SizedBox(height: 5),
        Text('Browse storage and pick up where you left off.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        if (lastPath.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(title: 'Continue browsing', trailing: 'Last location'),
          const SizedBox(height: 9),
          _HomeCard(
            onTap: onOpenLastLocation,
            child: Row(children: [
              _IconTile(icon: Icons.history_rounded, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lastPath.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(lastVolume == null ? 'Internal storage · $lastPath' : 'External storage · $lastPath',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ])),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ],
        if (favorites.isEmpty) ...[
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Favorites'),
          const SizedBox(height: 9),
          _HomeCard(
            child: Row(children: [
              _IconTile(icon: Icons.star_outline_rounded, color: colors.secondary),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Save files and folders from the More actions menu to find them here.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              )),
            ]),
          ),
        ],
        if (favorites.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionTitle(title: 'Favorites', trailing: '${favorites.length}'),
          const SizedBox(height: 9),
          _HomeCard(
            child: Column(children: [
              for (var index = 0; index < favorites.length; index++) ...[
                if (index > 0) Divider(height: 1, indent: 48, color: colors.outlineVariant.withValues(alpha: .35)),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  leading: _IconTile(
                    icon: favorites[index].isFolder ? Icons.folder_rounded : Icons.star_rounded,
                    color: colors.primary,
                    size: 38,
                  ),
                  title: Text(favorites[index].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(favorites[index].path, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => onOpenFavorite(favorites[index]),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 22),
        const _SectionTitle(title: 'Storage locations'),
        const SizedBox(height: 9),
        ...locations.map((location) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HomeCard(
            onTap: location.onTap,
            child: Row(children: [
              _IconTile(icon: location.icon, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(location.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(location.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ])),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        )),
        const SizedBox(height: 14),
        const _SectionTitle(title: 'Browse by type', trailing: 'Current location'),
        const SizedBox(height: 9),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 2.65,
          children: [
            _CategoryTile(label: 'Images', icon: Icons.photo_outlined, onTap: () => onBrowseCategory('Images')),
            _CategoryTile(label: 'Videos', icon: Icons.movie_outlined, onTap: () => onBrowseCategory('Videos')),
            _CategoryTile(label: 'Music', icon: Icons.music_note_rounded, onTap: () => onBrowseCategory('Music')),
            _CategoryTile(label: 'Documents', icon: Icons.description_outlined, onTap: () => onBrowseCategory('Documents')),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionTitle(title: 'Recent', trailing: '${recent.length}'),
          const SizedBox(height: 9),
          _HomeCard(
            child: Column(children: [
              for (var index = 0; index < recent.length; index++) ...[
                if (index > 0) Divider(height: 1, indent: 48, color: colors.outlineVariant.withValues(alpha: .35)),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  leading: _IconTile(
                    icon: recent[index].isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                    color: colors.secondary,
                    size: 38,
                  ),
                  title: Text(recent[index].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(recent[index].path.isEmpty ? 'Storage root' : recent[index].path,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => onOpenRecent(recent[index]),
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}

class _Location {
  const _Location({required this.title, required this.subtitle, required this.icon, required this.onTap});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
    const Spacer(),
    if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: child),
    ),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color, this.size = 44});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
    child: Icon(icon, color: color, size: 22),
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(children: [
            Icon(icon, color: colors.primary, size: 21),
            const SizedBox(width: 9),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant, size: 18),
          ]),
        ),
      ),
    );
  }
}
