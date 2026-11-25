import 'package:material_ui/material_ui.dart';

import '../../core/widgets/pocketlink_file_icon.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';
import '../../core/network/server_api.dart';

class FileEntryTile extends StatelessWidget {
  const FileEntryTile({
    required this.item,
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.formattedSize,
    required this.onOpen,
    required this.onDownload,
    required this.onRename,
    required this.onDelete,
    this.grid = false,
    super.key,
  });

  final FileEntry item;
  final ColorScheme colors;
  final IconData icon;
  final Color iconColor;
  final String formattedSize;
  final VoidCallback? onOpen;
  final VoidCallback onDownload;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool grid;

  Widget _fileIcon({double size = 24}) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: iconColor, size: size),
    );
  }

  Widget _actions({required double padding}) {
    return SmokedGlassPopoverMenu<String>(
      tooltip: 'More actions',
      items: [
        if (!item.isDirectory)
          const SmokedGlassPopoverMenuItem(
            value: 'download',
            label: 'Download',
            icon: Icons.download_rounded,
          ),
        const SmokedGlassPopoverMenuItem(
          value: 'rename',
          label: 'Rename',
          icon: Icons.drive_file_rename_outline_rounded,
        ),
        const SmokedGlassPopoverMenuItem(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          destructive: true,
          dividerBefore: true,
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case 'download':
            if (!item.isDirectory) onDownload();
            break;
          case 'rename':
            onRename();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: const Icon(Icons.more_vert_rounded),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!grid) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: SizedBox(
          height: 60,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: _fileIcon(),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              item.isDirectory ? 'Folder' : formattedSize,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            onTap: onOpen,
            trailing: _actions(padding: 8),
          ),
        ),
      );
    }

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _fileIcon(size: 26),
                  const Spacer(),
                  _actions(padding: 6),
                ],
              ),
              const Spacer(),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                item.isDirectory ? 'Folder' : formattedSize,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
