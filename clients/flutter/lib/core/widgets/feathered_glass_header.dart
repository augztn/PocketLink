import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'pocketlink_scaffold.dart';
import 'progressive_blur.dart';

/// Shared top-edge blur and legibility surface for edge-to-edge screens.
class FeatheredGlassHeaderBackground extends StatelessWidget {
  const FeatheredGlassHeaderBackground({
    this.darkTint,
    this.contentHeight = kToolbarHeight,
    this.strongestAtBottom = false,
    super.key,
  });

  final List<Color>? darkTint;
  final double contentHeight;
  final bool strongestAtBottom;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final headerHeight = media.padding.top + contentHeight + 16;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrimColor = isDark ? Colors.black : Colors.white;
    final customDarkTint = isDark && darkTint != null && darkTint!.length >= 3
        ? darkTint!
        : null;
    final scrimColors = customDarkTint == null
        ? [
            scrimColor.withValues(alpha: 0.92),
            scrimColor.withValues(alpha: 0.78),
            scrimColor.withValues(alpha: 0.48),
            scrimColor.withValues(alpha: 0.16),
            scrimColor.withValues(alpha: 0),
          ]
        : [
            customDarkTint[0],
            Color.lerp(customDarkTint[0], customDarkTint[1], 0.5)!,
            customDarkTint[1],
            Color.lerp(customDarkTint[1], customDarkTint[2], 0.5)!,
            customDarkTint[2],
          ];

    return _HeaderHeightReporter(
      height: headerHeight,
      child: SizedBox(
        width: double.infinity,
        height: headerHeight,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ProgressiveBlur(
                  maxSigma: 24,
                  steps: 14,
                  exponent: 1.6,
                  strongestAtBottom: strongestAtBottom,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: strongestAtBottom
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      end: strongestAtBottom
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      colors: scrimColors,
                      stops: const [0, 0.16, 0.38, 0.68, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reports a header's known geometry after layout, never during build.
class _HeaderHeightReporter extends StatefulWidget {
  const _HeaderHeightReporter({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  State<_HeaderHeightReporter> createState() => _HeaderHeightReporterState();
}

class _HeaderHeightReporterState extends State<_HeaderHeightReporter> {
  Route<dynamic>? _reportedRoute;
  double? _reportedHeight;
  bool _reportScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant _HeaderHeightReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.height - widget.height).abs() >= 0.5) {
      _scheduleReport();
    }
  }

  void _scheduleReport() {
    final route = ModalRoute.of(context);
    if (route == null || _reportScheduled ||
        (identical(_reportedRoute, route) &&
            _reportedHeight != null &&
            (_reportedHeight! - widget.height).abs() < 0.5)) {
      return;
    }

    final height = widget.height;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted || !identical(ModalRoute.of(context), route)) return;
      if (identical(_reportedRoute, route) &&
          _reportedHeight != null &&
          (_reportedHeight! - height).abs() < 0.5) {
        return;
      }
      LayoutInsetsScope.reportRenderedHeader(context, route, height);
      _reportedRoute = route;
      _reportedHeight = height;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Circular frosted action control for edge-to-edge headers.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.size = 38,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF0F172A);
    final button = CustomPaint(
      foregroundPainter: _GlassCircleRimPainter(isDark: isDark),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          splashColor: foreground.withValues(alpha: 0.08),
          highlightColor: Colors.transparent,
          child: Tooltip(
            message: tooltip,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF1C1E24).withValues(alpha: 0.58)
                    : Colors.white.withValues(alpha: 0.58),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.24)
                      : const Color(0xFF94A3B8).withValues(alpha: 0.30),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: IconTheme(
                  data: IconThemeData(color: foreground, size: 18),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return RepaintBoundary(
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: button,
        ),
      ),
    );
  }
}

class _GlassCircleRimPainter extends CustomPainter {
  const _GlassCircleRimPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = size.shortestSide;
    if (diameter <= 1) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [
                Color(0x99FFFFFF),
                Color(0x38FFFFFF),
                Color(0x08FFFFFF),
              ]
            : const [
                Color(0xAFFFFFFF),
                Color(0x54FFFFFF),
                Color(0x12FFFFFF),
              ],
        stops: const [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      diameter / 2 - 0.6,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassCircleRimPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
