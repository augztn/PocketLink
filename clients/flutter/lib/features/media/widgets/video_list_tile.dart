import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/smoked_glass_popover_menu.dart';

/// List presentation for a video. Playback and download behavior stay in the
/// media browser so the tile remains independent of screen state.
class VideoListTile extends StatelessWidget {
  const VideoListTile({
    required this.title,
    required this.extension,
    required this.sizeLabel,
    required this.sourceLabel,
    required this.artwork,
    required this.metadataLabel,
    required this.onOpen,
    required this.onDownload,
    super.key,
  });

  final String title;
  final String extension;
  final String sizeLabel;
  final String sourceLabel;
  final Widget artwork;
  final Widget metadataLabel;
  final VoidCallback onOpen;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          leading: Container(
            width: 104,
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: artwork,
          ),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$extension · $sizeLabel · $sourceLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              metadataLabel,
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmokedGlassPopoverMenu<String>(
                tooltip: 'Video actions',
                items: const [
                  SmokedGlassPopoverMenuItem(
                    value: 'download',
                    label: 'Download',
                    icon: Icons.download_rounded,
                  ),
                ],
                onSelected: (action) async {
                  if (action == 'download') await onDownload();
                },
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.more_vert_rounded),
                ),
              ),
              const Icon(Icons.play_circle_outline_rounded),
            ],
          ),
          onTap: onOpen,
        ),
      );
}
