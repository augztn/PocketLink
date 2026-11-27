import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Mirrors a downward drag from the top of scrollable Now Playing content
/// without competing with the scrollable's gesture recognizer.
class NowPlayingScrollDismissDetector extends StatefulWidget {
  const NowPlayingScrollDismissDetector({
    required this.child,
    this.enabled = true,
    this.scrollableKey,
    required this.onDismissDragStart,
    required this.onDismissDragUpdate,
    required this.onDismissDragEnd,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final GlobalKey? scrollableKey;
  final VoidCallback onDismissDragStart;
  final ValueChanged<double> onDismissDragUpdate;
  final ValueChanged<double> onDismissDragEnd;

  @override
  State<NowPlayingScrollDismissDetector> createState() =>
      _NowPlayingScrollDismissDetectorState();
}

class _NowPlayingScrollDismissDetectorState
    extends State<NowPlayingScrollDismissDetector> {
  static const double _touchSlop = 8;
  static const double _dismissDistance = 140;
  static const double _minimumDismissVelocity = 650;

  double _scrollOffset = 0;
  double _scrollOffsetAtPointerDown = 0;
  Offset? _pointerStart;
  Offset? _lastPointerPosition;
  VelocityTracker? _velocityTracker;
  bool _dismissDragStarted = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointerStart = event.position;
    _lastPointerPosition = event.position;
    _scrollOffsetAtPointerDown = _scrollOffset;
    final key = widget.scrollableKey;
    if (key != null) {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final bounds = renderObject.localToGlobal(Offset.zero) & renderObject.size;
        if (!bounds.contains(event.position)) _scrollOffsetAtPointerDown = 0;
      } else {
        _scrollOffsetAtPointerDown = 0;
      }
    }
    _dismissDragStarted = false;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.enabled) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    _applyPointerPosition(event.position);
  }

  void _applyPointerPosition(Offset position) {
    final start = _pointerStart;
    final previous = _lastPointerPosition;
    if (start == null || previous == null ||
        _scrollOffsetAtPointerDown > 0.5) {
      _lastPointerPosition = position;
      return;
    }

    final total = position - start;
    if (!_dismissDragStarted) {
      if (total.distance < _touchSlop ||
          total.dy <= 0 ||
          total.dy <= total.dx.abs() * 1.15) {
        return;
      }
      _dismissDragStarted = true;
      widget.onDismissDragStart();
      widget.onDismissDragUpdate(total.dy);
    } else {
      final delta = position.dy - previous.dy;
      if (delta != 0) widget.onDismissDragUpdate(delta);
    }
    _lastPointerPosition = position;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!widget.enabled) return;
    final tracker = _velocityTracker;
    if (tracker == null) {
      _resetPointer();
      return;
    }
    tracker.addPosition(event.timeStamp, event.position);
    _applyPointerPosition(event.position);
    final start = _pointerStart;
    final total = start == null ? Offset.zero : event.position - start;
    final velocity = tracker.getVelocity().pixelsPerSecond.dy;

    if (!_dismissDragStarted &&
        _scrollOffsetAtPointerDown <= 0.5 &&
        total.dy > 0 &&
        total.dy > total.dx.abs() * 1.15 &&
        (total.dy >= _dismissDistance ||
            velocity >= _minimumDismissVelocity)) {
      _dismissDragStarted = true;
      widget.onDismissDragStart();
      widget.onDismissDragUpdate(total.dy);
    }

    final shouldEnd = _dismissDragStarted;
    _resetPointer();
    if (shouldEnd) widget.onDismissDragEnd(velocity);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    final shouldEnd = _dismissDragStarted;
    _resetPointer();
    if (shouldEnd) widget.onDismissDragEnd(0);
  }

  void _resetPointer() {
    _pointerStart = null;
    _lastPointerPosition = null;
    _velocityTracker = null;
    _dismissDragStarted = false;
    _scrollOffsetAtPointerDown = 0;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.enabled && notification.depth == 0) {
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
          onPointerCancel: _handlePointerCancel,
          child: widget.child,
        ),
      );
}
