import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import 'persistent_audio_player.dart';

/// App-wide compact playback surface. The root shell owns visibility so this
/// remains mounted across Home, Explore and Files, but is hidden on Now Playing.
class PersistentMiniPlayer extends StatelessWidget {
  const PersistentMiniPlayer({
    required this.onOpenNowPlaying,
    super.key,
  });

  final VoidCallback onOpenNowPlaying;

  @override
  Widget build(BuildContext context) {
    final playback = PersistentAudioPlayer.instance;

    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final track = playback.currentItem;
        if (!playback.shouldShowMiniPlayer || track == null) {
          return const SizedBox.shrink();
        }

        final colors = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = colors.primary;
        final foreground = colors.onSurface;
        final muted = colors.onSurfaceVariant;

        return KeyedSubtree(
          key: PocketLinkNavigation.miniPlayerKey,
          child: LiquidGlassPill(
            radius: BorderRadius.circular(18),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 9),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                      ),
                      alignment: Alignment.center,
                      child: playback.isPlaying
                          ? _MiniPlayerEqualizer(color: accent)
                          : Icon(
                              Icons.music_note_rounded,
                              color: accent,
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: onOpenNowPlaying,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.97,
                                      end: 1,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: Text(
                                  track.title.replaceAll(
                                    RegExp(r'\.[^.]+$'),
                                    '',
                                  ),
                                  key: ValueKey<String>(track.path),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: foreground,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                playback.isPlaying
                                    ? 'NOW PLAYING · SWIPE TO SKIP'
                                    : 'PAUSED · SWIPE TO SKIP',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: muted,
                                      fontSize: 9,
                                      letterSpacing: 0.65,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous track',
                      visualDensity: VisualDensity.compact,
                      onPressed: playback.queue.length > 1
                          ? playback.player.previous
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: foreground.withValues(alpha: 0.78),
                    ),
                    IconButton(
                      tooltip: playback.isPlaying ? 'Pause' : 'Play',
                      visualDensity: VisualDensity.compact,
                      onPressed: playback.togglePlayback,
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      color: accent,
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      visualDensity: VisualDensity.compact,
                      onPressed: playback.queue.length > 1
                          ? playback.player.next
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                      color: foreground.withValues(alpha: 0.78),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerEqualizer extends StatefulWidget {
  const _MiniPlayerEqualizer({required this.color});

  final Color color;

  @override
  State<_MiniPlayerEqualizer> createState() => _MiniPlayerEqualizerState();
}

class _MiniPlayerEqualizerState extends State<_MiniPlayerEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          4,
          (index) => Container(
            width: 3,
            height: index.isEven ? 12 : 19,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(4, (index) {
          final phase = (_controller.value * math.pi * 2) + index * 1.15;
          final height = 8.0 + math.sin(phase).abs() * 14;
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
