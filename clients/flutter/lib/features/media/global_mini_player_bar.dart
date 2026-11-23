import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import 'persistent_audio_player.dart';

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

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        // Match the Home / Explore / Files capsule and leave Music outside it.
        padding: EdgeInsets.fromLTRB(
          hasFloatingNavBar ? 14 : 16,
          4,
          hasFloatingNavBar ? 88 : 16,
          0,
        ),
        child: SmokedGlassSurface(
          key: surfaceKey,
          radius: BorderRadius.circular(22),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: _handleHorizontalDrag,
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (!isPlaying && velocity > 300) onDismiss();
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
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
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
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(22),
                        ),
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
