import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

enum NowPlayingScrubberStyle {
  appleCapsule('apple', 'Apple Capsule'),
  wavy('wavy', 'Wavy Seekbar'),
  classic('classic', 'Classic Precision'),
  waveform('waveform', 'Waveform Bars');

  const NowPlayingScrubberStyle(this.key, this.label);
  final String key;
  final String label;

  static NowPlayingScrubberStyle fromKey(String? value) =>
      values.firstWhere((style) => style.key == value,
          orElse: () => NowPlayingScrubberStyle.appleCapsule);
}

class NowPlayingScrubber extends StatefulWidget {
  const NowPlayingScrubber({
    required this.style,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.isPlaying,
    required this.isBuffering,
    required this.onSeek,
    super.key,
  });

  final NowPlayingScrubberStyle style;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final bool isPlaying;
  final bool isBuffering;
  final ValueChanged<Duration> onSeek;

  @override
  State<NowPlayingScrubber> createState() => _NowPlayingScrubberState();
}

class _NowPlayingScrubberState extends State<NowPlayingScrubber>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _amplitude = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 0,
  );
  double? _dragProgress;

  bool get _hasDuration => widget.duration > Duration.zero;
  double get _progress => _hasDuration
      ? (widget.position.inMicroseconds / widget.duration.inMicroseconds)
          .clamp(0.0, 1.0)
          .toDouble()
      : 0;
  double get _bufferedProgress => _hasDuration
      ? (widget.bufferedPosition.inMicroseconds /
              widget.duration.inMicroseconds)
          .clamp(0.0, 1.0)
          .toDouble()
      : 0;
  bool get _showShimmer => widget.isBuffering || !_hasDuration;

  @override
  void initState() {
    super.initState();
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant NowPlayingScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimations();
  }

  void _syncAnimations() {
    if (_showShimmer) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
      _shimmer.value = 0;
    }
    if (widget.style == NowPlayingScrubberStyle.wavy &&
        widget.isPlaying &&
        !widget.isBuffering) {
      if (!_wave.isAnimating) _wave.repeat();
      _amplitude.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _wave.stop();
      _amplitude.animateTo(0, curve: Curves.easeOutCubic);
    }
  }

  Duration _durationAt(double progress) => Duration(
        microseconds:
            (widget.duration.inMicroseconds * progress).round(),
      );

  void _seekAt(double dx, double width) {
    if (!_hasDuration || width <= 0) return;
    final progress = (dx / width).clamp(0.0, 1.0).toDouble();
    setState(() => _dragProgress = progress);
  }

  void _commitSeek() {
    final progress = _dragProgress;
    if (progress == null || !_hasDuration) return;
    widget.onSeek(_durationAt(progress));
    setState(() => _dragProgress = null);
  }

  String _time(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 30);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _wave.dispose();
    _amplitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dragProgress ?? _progress;
    final style = widget.style;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (style == NowPlayingScrubberStyle.classic && _dragProgress != null)
          Align(
            alignment: Alignment(-1 + progress * 2, 0),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                _time(_durationAt(progress)),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              _seekAt(details.localPosition.dx, constraints.maxWidth);
              _commitSeek();
            },
            onHorizontalDragStart: (details) =>
                _seekAt(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _seekAt(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragEnd: (_) => _commitSeek(),
            onHorizontalDragCancel: () => setState(() => _dragProgress = null),
            child: AnimatedBuilder(
              animation: Listenable.merge([_shimmer, _wave, _amplitude]),
              builder: (context, _) => SizedBox(
                height: 24,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ScrubberPainter(
                    style: style,
                    progress: progress,
                    bufferedProgress: _bufferedProgress,
                    shimmer: _showShimmer ? _shimmer.value : null,
                    wavePhase: _wave.value,
                    waveAmplitude: 3.2 * _amplitude.value,
                    active: Colors.white,
                    inactive: Colors.white.withValues(alpha: 0.24),
                    buffered: Colors.white.withValues(alpha: 0.28),
                    dragging: _dragProgress != null,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _time(_dragProgress == null
                    ? widget.position
                    : _durationAt(progress)),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _hasDuration
                    ? '-${_time(widget.duration - _durationAt(progress))}'
                    : '--:--',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  const _ScrubberPainter({
    required this.style,
    required this.progress,
    required this.bufferedProgress,
    required this.shimmer,
    required this.wavePhase,
    required this.waveAmplitude,
    required this.active,
    required this.inactive,
    required this.buffered,
    required this.dragging,
  });

  final NowPlayingScrubberStyle style;
  final double progress;
  final double bufferedProgress;
  final double? shimmer;
  final double wavePhase;
  final double waveAmplitude;
  final Color active;
  final Color inactive;
  final Color buffered;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final left = 0.0;
    final right = size.width;
    final trackHeight = style == NowPlayingScrubberStyle.classic
        ? 3.0
        : style == NowPlayingScrubberStyle.appleCapsule && dragging
            ? 11.0
            : 6.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, centerY - trackHeight / 2, right, trackHeight),
      Radius.circular(trackHeight),
    );

    if (style == NowPlayingScrubberStyle.wavy) {
      final remaining = Paint()
        ..color = inactive
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(left, centerY), Offset(right, centerY), remaining);
      if (bufferedProgress > progress) {
        canvas.drawLine(
          Offset(right * progress, centerY),
          Offset(right * bufferedProgress, centerY),
          Paint()
            ..color = buffered
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
      if (progress > 0) {
        final path = Path();
        final end = right * progress;
        for (double x = 0; x <= end; x += 2) {
          final y = centerY +
              math.sin((x / 26 * math.pi * 2) + wavePhase * math.pi * 2) *
                  waveAmplitude;
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.lineTo(end, centerY);
        canvas.drawPath(
          path,
          Paint()
            ..color = active
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true,
        );
      }
      if (progress > 0) {
        final x = right * progress;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, centerY), width: 4, height: 16),
            const Radius.circular(3),
          ),
          Paint()..color = active,
        );
      }
      _paintShimmer(canvas, size);
      return;
    }

    canvas.drawRRect(track, Paint()..color = inactive);
    if (style != NowPlayingScrubberStyle.waveform && bufferedProgress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centerY - trackHeight / 2,
              right * bufferedProgress, trackHeight),
          Radius.circular(trackHeight),
        ),
        Paint()..color = buffered,
      );
    }

    if (style == NowPlayingScrubberStyle.waveform) {
      const count = 48;
      const gap = 2.0;
      final barWidth = (right - gap * (count - 1)) / count;
      for (var i = 0; i < count; i++) {
        final x = i * (barWidth + gap);
        final h = 4 + (math.sin(i * 1.73).abs() * 11);
        final barProgress = (i + 1) / count;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, centerY - h / 2, barWidth, h),
            const Radius.circular(2),
          ),
          Paint()
            ..color = barProgress <= progress
                ? active
                : barProgress <= bufferedProgress
                    ? buffered
                    : inactive,
        );
      }
    } else if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centerY - trackHeight / 2,
              right * progress, trackHeight),
          Radius.circular(trackHeight),
        ),
        Paint()..color = active,
      );
      if (style == NowPlayingScrubberStyle.classic) {
        canvas.drawCircle(
          Offset(right * progress, centerY),
          dragging ? 6 : 5,
          Paint()..color = active,
        );
      }
    }
    _paintShimmer(canvas, size);
  }

  void _paintShimmer(Canvas canvas, Size size) {
    final phase = shimmer;
    if (phase == null) return;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 7, size.width, 14),
      const Radius.circular(99),
    ));
    final start = -size.width + (size.width * 2 * phase);
    final shader = const LinearGradient(
      colors: [
        Color(0x00FFFFFF),
        Color(0x66FFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0, 0.5, 1],
    ).createShader(Rect.fromLTWH(start, 0, size.width, size.height));
    canvas.drawRect(rect, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter oldDelegate) =>
      style != oldDelegate.style ||
      progress != oldDelegate.progress ||
      bufferedProgress != oldDelegate.bufferedProgress ||
      shimmer != oldDelegate.shimmer ||
      wavePhase != oldDelegate.wavePhase ||
      waveAmplitude != oldDelegate.waveAmplitude ||
      dragging != oldDelegate.dragging;
}

class PlaybackLoadingIndicator extends StatelessWidget {
  const PlaybackLoadingIndicator({
    required this.loading,
    required this.size,
    required this.child,
    super.key,
  });

  final bool loading;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (loading)
              SizedBox(
                width: size - 3,
                height: size - 3,
                child: const CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white70,
                ),
              ),
            child,
          ],
        ),
      );
}

class BufferingBadge extends StatefulWidget {
  const BufferingBadge({super.key});

  @override
  State<BufferingBadge> createState() => _BufferingBadgeState();
}

class _BufferingBadgeState extends State<BufferingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _pulse,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white24),
          ),
          child: const Text(
            'BUFFERING',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
      );

}

class NowPlayingScrubberPreview extends StatelessWidget {
  const NowPlayingScrubberPreview({required this.style, super.key});
  final NowPlayingScrubberStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 30,
        child: CustomPaint(
          painter: _ScrubberPainter(
            style: style,
            progress: 0.42,
            bufferedProgress: 0.68,
            shimmer: null,
            wavePhase: 0.25,
            waveAmplitude: style == NowPlayingScrubberStyle.wavy ? 3.2 : 0,
            active: Colors.white,
            inactive: Colors.white24,
            buffered: Colors.white.withValues(alpha: 0.28),
            dragging: false,
          ),
        ),
      );
}
