import 'package:material_ui/material_ui.dart';

/// Breadcrumb navigation for the media browser's folder view.
class MediaFolderBreadcrumbs extends StatelessWidget {
  const MediaFolderBreadcrumbs({
    required this.currentPath,
    required this.volumeLabel,
    required this.onAllStorage,
    required this.onVolumeRoot,
    required this.onFolder,
    super.key,
  });

  final String currentPath;
  final String? volumeLabel;
  final VoidCallback onAllStorage;
  final VoidCallback onVolumeRoot;
  final ValueChanged<String> onFolder;

  @override
  Widget build(BuildContext context) {
    final parts = currentPath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (currentPath.isEmpty && volumeLabel == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 38,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TextButton(
              onPressed: currentPath.isEmpty && volumeLabel == null
                  ? null
                  : onAllStorage,
              child: const Text('All storage'),
            ),
            if (volumeLabel != null) ...[
              const Icon(Icons.chevron_right_rounded, size: 16),
              TextButton(
                onPressed: currentPath.isEmpty ? null : onVolumeRoot,
                child: Text(volumeLabel!),
              ),
            ],
            for (var i = 0; i < parts.length; i++) ...[
              const Icon(Icons.chevron_right_rounded, size: 16),
              TextButton(
                onPressed: i == parts.length - 1
                    ? null
                    : () => onFolder(parts.take(i + 1).join('/')),
                child: Text(parts[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
