import 'package:material_ui/material_ui.dart';

import 'media_library_catalog.dart';

/// A single music-library row. Playback, selection, favorites, queueing, and
/// downloads remain owned by the media browser.
class MusicTrackTile extends StatelessWidget {
  const MusicTrackTile({
    required this.title,
    required this.artist,
    required this.artwork,
    required this.duration,
    required this.playing,
    required this.selected,
    required this.favorite,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onPlayNext,
    required this.onQueue,
    required this.onDownload,
    required this.onToggleFavorite,
    super.key,
  });

  final String title;
  final String artist;
  final Widget artwork;
  final Widget duration;
  final bool playing;
  final bool selected;
  final bool favorite;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onQueue;
  final Future<void> Function() onDownload;
  final Future<void> Function() onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0x22536DFE)
          : playing
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              artwork,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E939E),
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              duration,
              if (selectionMode)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 18,
                    color: selected
                        ? const Color(0xFF536DFE)
                        : const Color(0xFF8E939E),
                  ),
                )
              else
                SmokedGlassPopoverMenu<String>(
                  tooltip: 'Track actions',
                  items: [
                    const SmokedGlassPopoverMenuItem(
                      value: 'next',
                      label: 'Play next',
                      icon: Icons.skip_next_rounded,
                    ),
                    const SmokedGlassPopoverMenuItem(
                      value: 'queue',
                      label: 'Add to queue',
                      icon: Icons.queue_music_rounded,
                    ),
                    const SmokedGlassPopoverMenuItem(
                      value: 'download',
                      label: 'Download',
                      icon: Icons.download_rounded,
                      dividerBefore: true,
                    ),
                    SmokedGlassPopoverMenuItem(
                      value: 'favorite',
                      label: favorite
                          ? 'Remove favourite'
                          : 'Add to favourites',
                      icon: favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                  ],
                  onSelected: (action) async {
                    if (action == 'favorite') await onToggleFavorite();
                    if (action == 'next') await onPlayNext();
                    if (action == 'queue') await onQueue();
                    if (action == 'download') await onDownload();
                  },
                  child: const SizedBox(
                    width: 28,
                    height: 36,
                    child: Center(
                      child: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: Color(0xFF8E939E),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
