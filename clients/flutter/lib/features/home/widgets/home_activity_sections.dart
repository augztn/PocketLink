import 'package:material_ui/material_ui.dart';

import '../../../core/storage/home_activity_store.dart';
import '../../../core/widgets/smoked_glass_popover_menu.dart';
import '../../../core/network/server_api.dart';

class HomeContinueSection extends StatelessWidget {
  const HomeContinueSection({
    required this.items,
    required this.cardDecoration,
    required this.onBrowseMedia,
    required this.onSelectItem,
    super.key,
  });

  final List<HomeActivityItem> items;
  final BoxDecoration Function(ThemeData theme) cardDecoration;
  final VoidCallback onBrowseMedia;
  final ValueChanged<HomeActivityItem> onSelectItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: cardDecoration(theme),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, color: colors.onSurfaceVariant, size: 22),
            const SizedBox(height: 7),
            Text(
              'Your recent tracks, folders and files will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onBrowseMedia,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8C9EFF),
                backgroundColor: const Color(0xFF536DFE).withValues(alpha: 0.16),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 17),
              label: const Text('Browse media'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final isTrack = item.kind == 'track';
          final isFolder = item.isFolder;
          final icon = isTrack
              ? Icons.music_note_rounded
              : isFolder
                  ? Icons.folder_rounded
                  : Icons.insert_drive_file_rounded;
          return SizedBox(
            width: 250,
            child: Container(
              decoration: cardDecoration(theme),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSelectItem(item),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: colors.primary),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTrack ? 'Continue listening' : isFolder ? 'Recent folder' : 'Recent file',
                                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Icon(isTrack ? Icons.play_arrow_rounded : Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HomeRecentFilesSection extends StatelessWidget {
  const HomeRecentFilesSection({
    required this.files,
    required this.error,
    required this.checking,
    required this.cardDecoration,
    required this.formatBytes,
    required this.relativeTime,
    required this.iconForFile,
    required this.onBrowse,
    required this.onFileTap,
    required this.onAction,
    super.key,
  });

  final List<RecentFile> files;
  final String? error;
  final bool checking;
  final BoxDecoration Function(ThemeData theme, {double radius}) cardDecoration;
  final String Function(int bytes) formatBytes;
  final String Function(DateTime date) relativeTime;
  final IconData Function(FileEntry file) iconForFile;
  final VoidCallback onBrowse;
  final ValueChanged<RecentFile> onFileTap;
  final void Function(RecentFile file, String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent files',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            TextButton(onPressed: onBrowse, child: const Text('Browse')),
          ],
        ),
        const SizedBox(height: 10),
        if (files.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: cardDecoration(theme, radius: 20),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: colors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    error ?? (checking
                        ? 'Checking your folders for recent files…'
                        : 'No recent files found in the scanned folders.'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: cardDecoration(theme, radius: 20),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < files.take(8).length; index++) ...[
                    if (index > 0) const Divider(height: 1, indent: 68),
                    ListTile(
                      dense: true,
                      minVerticalPadding: 8,
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(iconForFile(files[index].file), color: colors.onSecondaryContainer),
                      ),
                      title: Text(
                        files[index].file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatBytes(files[index].file.size)} · ${relativeTime(files[index].modifiedAt)} · ${files[index].volumeName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SmokedGlassPopoverMenu<String>(
                        tooltip: 'File actions',
                        items: const [
                          SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded),
                          SmokedGlassPopoverMenuItem(value: 'share', label: 'Share', icon: Icons.ios_share_rounded),
                          SmokedGlassPopoverMenuItem(value: 'rename', label: 'Rename', icon: Icons.drive_file_rename_outline_rounded),
                          SmokedGlassPopoverMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true, dividerBefore: true),
                        ],
                        onSelected: (action) => onAction(files[index], action),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.more_vert_rounded, size: 18),
                        ),
                      ),
                      onTap: () => onFileTap(files[index]),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
