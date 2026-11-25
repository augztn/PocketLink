import 'package:material_ui/material_ui.dart';

import '../../core/network/server_api.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';

/// Storage selector title for the file browser. Selection and menu state stay
/// owned by FileManagerScreen.
class FileBrowserStorageTitle extends StatelessWidget {
  const FileBrowserStorageTitle({
    required this.path,
    required this.folderCount,
    required this.fileCount,
    required this.volumes,
    required this.selectedVolume,
    required this.menuOpen,
    required this.onOpenChanged,
    required this.onSelected,
    super.key,
  });

  final String path;
  final int folderCount;
  final int fileCount;
  final List<StorageVolume> volumes;
  final String? selectedVolume;
  final bool menuOpen;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return TitleDropdownPopover<String>(
      tooltip: 'Choose storage location',
      onOpenChanged: onOpenChanged,
      items: [
        SmokedGlassPopoverMenuItem(
          value: 'internal',
          label: 'Internal storage',
          icon: Icons.phone_android_rounded,
          trailing: SizedBox(
            width: 20,
            child: selectedVolume == null
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
          ),
        ),
        for (final volume in volumes)
          SmokedGlassPopoverMenuItem(
            value: volume.id,
            label: volume.name,
            icon: Icons.usb_rounded,
            trailing: SizedBox(
              width: 20,
              child: selectedVolume == volume.id
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
            ),
          ),
        const SmokedGlassPopoverMenuItem(
          value: 'downloads',
          label: 'Downloads',
          icon: Icons.download_rounded,
          dividerBefore: true,
        ),
        const SmokedGlassPopoverMenuItem(
          value: 'recent',
          label: 'Recent',
          icon: Icons.history_rounded,
        ),
      ],
      onSelected: onSelected,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        path.isEmpty ? 'Files' : path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: menuOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${folderCount == 1 ? '1 folder' : '$folderCount folders'} • '
                  '${fileCount == 1 ? '1 file' : '$fileCount files'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Color(0xFFA1A7B3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
