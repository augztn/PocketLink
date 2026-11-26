import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
import 'pocketlink_scaffold.dart';
import 'progressive_blur.dart';

/// Single source of truth for the top-edge blur used by every PocketLink section.
///
/// Change these values once to update all shared headers consistently.
abstract final class PocketLinkHeaderBlurStyle {
  static const double sigma = 24.0;
  static const List<Color> darkScrim = [
    Color(0xE6000000),
    Color(0xD9000000),
    Color(0xB3000000),
    Color(0x59000000),
    Colors.transparent,
  ];
  static const List<double> scrimStops = [0.0, 0.16, 0.38, 0.68, 1.0];
}

/// Shared top-edge blur and legibility surface for edge-to-edge screens.
///
/// Legacy per-screen styling arguments remain accepted for source compatibility,
/// but are intentionally ignored: blur strength, direction, fade and scrim are
/// global so every section renders the same header treatment.
class FeatheredGlassHeaderBackground extends StatelessWidget {
  const FeatheredGlassHeaderBackground({
    List<Color>? darkTint,
    this.contentHeight = kToolbarHeight,
    this.topInset,
    bool? strongestAtBottom,
    bool? fadeTailOnly,
    bool? toolbarSegmentOnly,
    super.key,
  });

  final double contentHeight;
  final double? topInset;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final effectiveTopInset = topInset ?? media.padding.top;
    final headerHeight = effectiveTopInset + contentHeight;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _HeaderHeightReporter(
      height: headerHeight,
      child: SizedBox(
        width: double.infinity,
        height: headerHeight,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: AppSettings.instance,
            builder: (context, _) {
              final backdrop = isDark
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: PocketLinkHeaderBlurStyle.darkScrim,
                          stops: PocketLinkHeaderBlurStyle.scrimStops,
                        ),
                      ),
                      child: SizedBox.expand(),
                    )
                  : const SizedBox.expand();
              if (!AppSettings.instance.progressiveBlurEnabled) {
                return backdrop;
              }
              return ProgressiveBlur(
                maxSigma: PocketLinkHeaderBlurStyle.sigma,
                endSigma: 0,
                strongestAtBottom: false,
                child: backdrop,
              );
            },
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
