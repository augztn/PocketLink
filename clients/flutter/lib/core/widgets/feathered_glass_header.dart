import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
import 'pocketlink_scaffold.dart';
import 'progressive_blur.dart';

/// Shared progressive blur and legibility surface for edge-to-edge screens.
class FeatheredGlassHeaderBackground extends StatefulWidget {
  const FeatheredGlassHeaderBackground({
    this.darkTint,
    this.contentHeight = kToolbarHeight,
    super.key,
  });

  final List<Color>? darkTint;
  final double contentHeight;

  @override
  State<FeatheredGlassHeaderBackground> createState() =>
      _FeatheredGlassHeaderBackgroundState();
}

class _FeatheredGlassHeaderBackgroundState
    extends State<FeatheredGlassHeaderBackground> {
  ScrollController? _scrollController;
  bool _isScrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = PrimaryScrollController.maybeOf(context);
    if (identical(nextController, _scrollController)) return;
    _scrollController?.removeListener(_handleScroll);
    _scrollController = nextController;
    _scrollController?.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollState();
    });
    _updateScrollState();
  }

  @override
  void dispose() {
    _scrollController?.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() => _updateScrollState();

  void _updateScrollState() {
    final controller = _scrollController;
    final scrolled = controller != null &&
        controller.hasClients &&
        controller.positions.any((position) => position.pixels > 0);
    if (scrolled != _isScrolled && mounted) {
      setState(() => _isScrolled = scrolled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final settings = AppSettings.instance;
        const blurScale = 1.0;
        final useBlur = settings.progressiveBlurEnabled && _isScrolled;
        final headerHeight =
            media.padding.top + widget.contentHeight + pocketLinkHeaderFadeTailHeight;
        final scrimBase = theme.scaffoldBackgroundColor;
        final scrimColor = isDark ? Colors.black : Colors.white;
        final scrimColors = [
          scrimColor.withValues(alpha: 0.94),
          scrimColor.withValues(alpha: 0.78),
          scrimColor.withValues(alpha: 0.48),
          scrimColor.withValues(alpha: 0.16),
          scrimColor.withValues(alpha: 0),
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
                  if (useBlur) ...[
                    _buildProgressiveBlur(
                      height: headerHeight,
                      blurScale: blurScale,
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: scrimColors,
                            stops: const [0.0, 0.18, 0.42, 0.72, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ] else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.darkTint != null && isDark
                              ? widget.darkTint!
                              : [
                                  scrimBase,
                                  scrimBase.withValues(alpha: 0.72),
                                  Colors.transparent,
                                ],
                          stops: widget.darkTint != null && isDark
                              ? const [0, 0.48, 1]
                              : const [0, 0.55, 1],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressiveBlur({
    required double height,
    required double blurScale,
  }) {
    return ProgressiveBlur(
      maxSigma: 22 * blurScale,
      steps: 14,
      exponent: 1.6,
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
    final settings = AppSettings.instance;
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
                  ? const Color(0xFF141518).withValues(alpha: 0.66)
                  : Colors.white.withValues(alpha: 0.68),
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

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final useBlur = settings.useLiquidGlass;
        return RepaintBoundary(
          child: ClipOval(
            child: useBlur
                ? BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: 20,
                      sigmaY: 20,
                      tileMode: ui.TileMode.clamp,
                    ),
                    child: button,
                  )
                : button,
          ),
        );
      },
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
      ..strokeWidth = 0.85
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [
                Color(0x23FFFFFF),
                Color(0x12FFFFFF),
                Color(0x0AFFFFFF),
              ]
            : const [
                Color(0x23FFFFFF),
                Color(0x12FFFFFF),
                Color(0x0AFFFFFF),
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
