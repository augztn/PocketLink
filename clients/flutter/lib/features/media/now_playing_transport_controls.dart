import 'package:material_ui/material_ui.dart';

import 'now_playing_scrubber.dart';

/// Stream-driven transport controls for the expanded Now Playing screen.
class NowPlayingTransportControls extends StatelessWidget {
  const NowPlayingTransportControls({
    required this.playing,
    required this.buffering,
    required this.duration,
    required this.initialPlaying,
    required this.initialBuffering,
    required this.initialDuration,
    required this.selectionLoading,
    required this.hasMultipleTracks,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    super.key,
  });

  final Stream<bool> playing;
  final Stream<bool> buffering;
  final Stream<Duration> duration;
  final bool initialPlaying;
  final bool initialBuffering;
  final Duration initialDuration;
  final bool Function() selectionLoading;
  final bool Function() hasMultipleTracks;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: playing,
        initialData: initialPlaying,
        builder: (context, playingSnapshot) => StreamBuilder<bool>(
          stream: buffering,
          initialData: initialBuffering,
          builder: (context, bufferingSnapshot) => StreamBuilder<Duration>(
            stream: duration,
            initialData: initialDuration,
            builder: (context, durationSnapshot) {
              final isPlaying = playingSnapshot.data ?? false;
              final loading = selectionLoading() ||
                  (bufferingSnapshot.data ?? false) ||
                  (durationSnapshot.data ?? Duration.zero) <= Duration.zero;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _TransportGlyph(
                    tooltip: 'Previous track',
                    icon: Icons.fast_rewind_rounded,
                    size: 42,
                    enabled: hasMultipleTracks(),
                    onTap: onPrevious,
                  ),
                  PlaybackLoadingIndicator(
                    loading: loading,
                    size: 78,
                    child: _TransportGlyph(
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      icon: isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 58,
                      enabled: !loading,
                      onTap: onPlayPause,
                    ),
                  ),
                  _TransportGlyph(
                    tooltip: 'Next track',
                    icon: Icons.fast_forward_rounded,
                    size: 42,
                    enabled: hasMultipleTracks(),
                    onTap: onNext,
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _TransportGlyph extends StatefulWidget {
  const _TransportGlyph({
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_TransportGlyph> createState() => _TransportGlyphState();
}

class _TransportGlyphState extends State<_TransportGlyph> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: SizedBox(
            width: 78,
            height: 78,
            child: Center(
              child: AnimatedScale(
                scale: _pressed ? 0.88 : 1,
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                child: Icon(
                  widget.icon,
                  size: widget.size,
                  color: Colors.white.withValues(
                    alpha: widget.enabled ? 1 : 0.32,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
