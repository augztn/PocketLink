import 'dart:typed_data';

import 'package:flutter/gestures.dart';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import 'persistent_audio_player.dart';
import 'now_playing_artwork_palette.dart';
import 'track_artwork_view.dart';

/// Compact, app-wide music controls shown above the navigation dock.
class GlobalMiniPlayerBar extends StatelessWidget {
  const GlobalMiniPlayerBar({
    required this.item,
    required this.visible,
    required this.reduceMotion,
    required this.isPlaying,
    this.isLoading = false,
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
    this.onExpandDragStart,
    this.onExpandDragUpdate,
    this.onExpandDragEnd,
    super.key,
  });

  final MediaQueueItem item;
  final bool visible;
  final bool reduceMotion;
  final bool isPlaying;
  final bool isLoading;
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
  final VoidCallback? onExpandDragStart;
  final ValueChanged<double>? onExpandDragUpdate;
  final ValueChanged<double>? onExpandDragEnd;

  double get _progress {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final foreground = isLight ? const Color(0xFF0F172A) : colors.onSurface;
    final secondaryForeground =
        isLight ? const Color(0xFF475569) : colors.onSurfaceVariant;

    final safeInsets = MediaQuery.paddingOf(context);
    final pathParts = item.path.split('/');
    final folderName = pathParts.length > 1
        ? pathParts[pathParts.length - 2]
        : 'Internal storage';
    final artworkPalette = NowPlayingArtworkPalette.fallback(
      title: item.title,
      folderName: folderName,
      path: item.path,
    );

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
        // Fade the entire docked surface, not just its controls. The opaque
        // glass shell otherwise remains above the morph overlay as a grey box.
        child: Opacity(
          opacity: visible ? 1 : 0,
          child: SmokedGlassSurface(
            key: surfaceKey,
            radius: BorderRadius.circular(22),
            intensity: surfaceIntensity,
            child: _MiniPlayerGestureSurface(
              onTap: onOpen,
              onDismiss: onDismiss,
              isPlaying: isPlaying,
              canSkipPrevious: canSkipPrevious,
              canSkipNext: canSkipNext,
              onExpandDragStart: onExpandDragStart,
              onExpandDragUpdate: onExpandDragUpdate,
              onExpandDragEnd: onExpandDragEnd,
              onHorizontalSkipNext: onSkipNext,
              onHorizontalSkipPrevious: onSkipPrevious,
              child: Material(
                  type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(22),
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
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: TrackArtworkView(
                                bytes: artworkBytes,
                                artworkUrl: item.artworkUrl,
                                fallbackColors: artworkPalette,
                                fallbackIconSize: 19,
                                borderRadius: BorderRadius.circular(11),
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
                                        ? (item.artist?.trim().isNotEmpty == true
                                            ? item.artist!.trim()
                                            : item.sourceLabel)
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
                              onPressed: isLoading ? null : onTogglePlayback,
                              color: foreground,
                              icon: isLoading
                                  ? SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(foreground),
                                      ),
                                    )
                                  : Icon(
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
    );
  }
}

/// Uses axis-specific recognizers so vertical expansion cannot be lost to
/// horizontal track-skip handling or child tap controls.
class _MiniPlayerGestureSurface extends StatefulWidget {
  const _MiniPlayerGestureSurface({
    required this.child,
    required this.onTap,
    required this.onDismiss,
    required this.isPlaying,
    required this.canSkipPrevious,
    required this.canSkipNext,
    required this.onExpandDragStart,
    required this.onExpandDragUpdate,
    required this.onExpandDragEnd,
    required this.onHorizontalSkipNext,
    required this.onHorizontalSkipPrevious,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final bool isPlaying;
  final bool canSkipPrevious;
  final bool canSkipNext;
  final VoidCallback? onExpandDragStart;
  final ValueChanged<double>? onExpandDragUpdate;
  final ValueChanged<double>? onExpandDragEnd;
  final VoidCallback onHorizontalSkipNext;
  final VoidCallback onHorizontalSkipPrevious;

  @override
  State<_MiniPlayerGestureSurface> createState() =>
      _MiniPlayerGestureSurfaceState();
}

class _MiniPlayerGestureSurfaceState extends State<_MiniPlayerGestureSurface> {
  bool _expandStarted = false;
  double _verticalDistance = 0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.delta.dy;
    _verticalDistance += delta;
    if (!_expandStarted && _verticalDistance < 0) {
      _expandStarted = true;
      widget.onExpandDragStart?.call();
      widget.onExpandDragUpdate?.call(_verticalDistance);
      return;
    }
    if (_expandStarted) widget.onExpandDragUpdate?.call(delta);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_expandStarted) {
      widget.onExpandDragEnd?.call(velocity);
    } else if (!widget.isPlaying && velocity > 300) {
      widget.onDismiss();
    }
    _reset();
  }

  void _onVerticalDragCancel() {
    if (_expandStarted) widget.onExpandDragEnd?.call(0);
    _reset();
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity < -300 && widget.canSkipNext) {
      widget.onHorizontalSkipNext();
    } else if (velocity > 300 && widget.canSkipPrevious) {
      widget.onHorizontalSkipPrevious();
    }
  }

  void _reset() {
    _expandStarted = false;
    _verticalDistance = 0;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: widget.onTap,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        onVerticalDragCancel: _onVerticalDragCancel,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: widget.child,
      );
}
