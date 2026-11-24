import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import 'persistent_audio_player.dart';
import 'discover/discover_thumbnail_cache.dart';

/// Compact, app-wide music controls shown above the navigation dock.
class GlobalMiniPlayerBar extends StatelessWidget {
  const GlobalMiniPlayerBar({
    required this.item,
    required this.visible,
    required this.reduceMotion,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.canSkipPrevious,
    required this.canSkipNext,
    required this.onOpen,
    required this.onDismiss,
    required this.onTogglePlayback,
    required this.onSkipPrevious,
    required this.onSkipNext,
    this.surfaceKey,
    this.hasFloatingNavBar = true,
    this.compact = false,
    this.surfaceIntensity = 1.0,
    this.artworkBytes,
    this.artworkKey,
    this.onExpandDragUpdate,
    this.onExpandDragEnd,
    super.key,
  });

  final MediaQueueItem item;
  final bool visible;
  final bool reduceMotion;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool canSkipPrevious;
  final bool canSkipNext;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final Key? surfaceKey;
  final bool hasFloatingNavBar;
  final bool compact;
  final double surfaceIntensity;
  final Uint8List? artworkBytes;
  final Key? artworkKey;
  final ValueChanged<double>? onExpandDragUpdate;
  final ValueChanged<double>? onExpandDragEnd;

  double get _progress {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _handleHorizontalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300 && canSkipNext) {
      onSkipNext();
    } else if (velocity > 300 && canSkipPrevious) {
      onSkipPrevious();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final foreground = isLight ? const Color(0xFF0F172A) : colors.onSurface;
    final secondaryForeground =
        isLight ? const Color(0xFF475569) : colors.onSurfaceVariant;

    final safeInsets = MediaQuery.paddingOf(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        // Match the full 3+1 dock width, including the circular Music button.
        padding: compact
            ? const EdgeInsets.only(top: 4)
            : EdgeInsets.fromLTRB(
                safeInsets.left + 16.0,
                4,
                safeInsets.right + 16.0,
                0,
              ),
        child: SmokedGlassSurface(
          key: surfaceKey,
          radius: BorderRadius.circular(22),
          intensity: surfaceIntensity,
          // The overlay paints the shared morphing player while expanding.
          // Hide this docked source immediately so two control sets never overlap.
          child: Opacity(
            opacity: visible ? 1 : 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: _handleHorizontalDrag,
              onVerticalDragUpdate: onExpandDragUpdate == null
                  ? null
                  : (details) =>
                      onExpandDragUpdate!(details.primaryDelta ?? 0),
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (onExpandDragEnd != null) {
                  onExpandDragEnd!(velocity);
                } else if (!isPlaying && velocity > 300) {
                  onDismiss();
                }
              },
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onOpen,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 55,
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            Container(
                              key: artworkKey,
                              width: 34,
                              height: 34,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: artworkBytes != null
                                  ? Image.memory(
                                      artworkBytes!,
                                      cacheWidth: 544,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    )
                                  : item.artworkUrl?.isNotEmpty == true
                                      ? DiscoverThumbnail(
                                          url: item.artworkUrl!,
                                          cacheWidth: 544,
                                          fallback: Icon(
                                            Icons.graphic_eq_rounded,
                                            color: colors.primary,
                                            size: 19,
                                          ),
                                        )
                                      : Icon(
                                          Icons.graphic_eq_rounded,
                                          color: colors.primary,
                                          size: 19,
                                        ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: foreground,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  Text(
                                    isPlaying
                                        ? 'NOW PLAYING · SWIPE TO SKIP'
                                        : 'PAUSED',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontSize: 8,
                                          letterSpacing: 0.45,
                                          color: secondaryForeground,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Previous track',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 40,
                              ),
                              onPressed:
                                  canSkipPrevious ? onSkipPrevious : null,
                              color: foreground,
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                size: 20,
                              ),
                            ),
                            IconButton(
                              tooltip: isPlaying ? 'Pause' : 'Play',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 34,
                                height: 40,
                              ),
                              onPressed: onTogglePlayback,
                              color: foreground,
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 22,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next track',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 40,
                              ),
                              onPressed: canSkipNext ? onSkipNext : null,
                              color: foreground,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(19, 0, 19, 3),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 2.5,
                            backgroundColor:
                                colors.onSurface.withValues(alpha: 0.07),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colors.primary.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
