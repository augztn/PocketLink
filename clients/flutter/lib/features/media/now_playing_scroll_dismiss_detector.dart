import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Adds a downward-dismiss fallback to scrollable Now Playing content without
/// taking vertical gestures away from the scrollable itself.
class NowPlayingScrollDismissDetector extends StatefulWidget {
  const NowPlayingScrollDismissDetector({
    required this.child,
    required this.onDismissDragStart,
    required this.onDismissDragUpdate,
    required this.onDismissDragEnd,
    super.key,
  });

  final Widget child;
  final VoidCallback onDismissDragStart;
  final ValueChanged<double> onDismissDragUpdate;
  final ValueChanged<double> onDismissDragEnd;

  @override
  State<NowPlayingScrollDismissDetector> createState() =>
      _NowPlayingScrollDismissDetectorState();
}

class _NowPlayingScrollDismissDetectorState
    extends State<NowPlayingScrollDismissDetector> {
  static const double _dismissDistance = 140;
  static const double _minimumDismissVelocity = 650;

  double _scrollOffset = 0;
  double _scrollOffsetAtPointerDown = 0;
  Offset? _pointerStart;
  VelocityTracker? _velocityTracker;

  void _handlePointerDown(PointerDownEvent event) {
    _pointerStart = event.position;
    _scrollOffsetAtPointerDown = _scrollOffset;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _velocityTracker?.addPosition(event.timeStamp, event.position);
  }

  void _handlePointerUp(PointerUpEvent event) {
    final start = _pointerStart;
    final tracker = _velocityTracker;
    _resetPointer();
    if (start == null || tracker == null || _scrollOffsetAtPointerDown > 0.5) {
      return;
    }

    tracker.addPosition(event.timeStamp, event.position);
    final delta = event.position - start;
    final velocity = tracker.getVelocity().pixelsPerSecond.dy;
    final isDownwardSwipe = delta.dy > 0 && delta.dy > delta.dx.abs() * 1.15;
    if (!isDownwardSwipe ||
        (delta.dy < _dismissDistance &&
            velocity < _minimumDismissVelocity)) {
      return;
    }

    widget.onDismissDragStart();
    widget.onDismissDragUpdate(delta.dy);
    widget.onDismissDragEnd(velocity);
  }

  void _resetPointer() {
    _pointerStart = null;
    _velocityTracker = null;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0) {
      _scrollOffset = notification.metrics.pixels;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: (_) => _resetPointer(),
          child: widget.child,
        ),
      );
}
