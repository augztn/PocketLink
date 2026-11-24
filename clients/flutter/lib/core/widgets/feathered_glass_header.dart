import 'dart:ui' as ui;

final Future<ui.FragmentProgram> _progressiveBlurProgram =
    ui.FragmentProgram.fromAsset('shaders/progressive_blur.frag');

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
import 'pocketlink_scaffold.dart';

/// Shared app-wide glass blur and legibility surface for screen headers.
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
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final settings = AppSettings.instance;
        final useBlur = settings.progressiveBlurEnabled;
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
                    _buildProgressiveBlur(headerHeight),
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

}

  Widget _blurBand({
    required double top,
    required double bottom,
    required double height,
    required double sigma,
  }) {
    return Positioned(
      top: height * top,
      left: 0,
      right: 0,
      height: height * (bottom - top),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.clamp,
          ),
          child: const ColoredBox(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildProgressiveBlur(double height) {
    final fallback = _buildSteppedBlur(height);
    if (!ui.ImageFilter.isShaderFilterSupported) return fallback;

    return FutureBuilder<ui.FragmentProgram>(
      future: _progressiveBlurProgram,
      builder: (context, snapshot) {
        final program = snapshot.data;
        if (program == null) return fallback;
        return _ProgressiveShaderBackdropFilter(
          program: program,
          sigma: 18,
          fadeStart: 0.42,
          fadeEnd: 1,
        );
      },
    );
  }

  Widget _buildSteppedBlur(double height) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _blurBand(top: 0, bottom: 0.35, height: height, sigma: 18),
        _blurBand(top: 0.35, bottom: 0.55, height: height, sigma: 12),
        _blurBand(top: 0.55, bottom: 0.72, height: height, sigma: 7),
        _blurBand(top: 0.72, bottom: 0.86, height: height, sigma: 3.5),
        _blurBand(top: 0.86, bottom: 1, height: height, sigma: 1.2),
      ],
    );
  }
}

/// One Gaussian backdrop blur followed by Mochy's shader feather mask.
class _ProgressiveShaderBackdropFilter extends StatefulWidget {
  const _ProgressiveShaderBackdropFilter({
    required this.program,
    required this.sigma,
    required this.fadeStart,
    required this.fadeEnd,
  });

  final ui.FragmentProgram program;
  final double sigma;
  final double fadeStart;
  final double fadeEnd;

  @override
  State<_ProgressiveShaderBackdropFilter> createState() =>
      _ProgressiveShaderBackdropFilterState();
}

class _ProgressiveShaderBackdropFilterState
    extends State<_ProgressiveShaderBackdropFilter> {
  late final ui.FragmentShader _shader;
  late ui.ImageFilter _filter;

  @override
  void initState() {
    super.initState();
    _shader = widget.program.fragmentShader();
    _updateUniforms();
    _filter = _createFilter();
  }

  @override
  void didUpdateWidget(covariant _ProgressiveShaderBackdropFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fadeStart != widget.fadeStart ||
        oldWidget.fadeEnd != widget.fadeEnd) {
      _updateUniforms();
    }
    if (oldWidget.sigma != widget.sigma) {
      _filter = _createFilter();
    }
  }

  void _updateUniforms() {
    _shader.setFloat(2, widget.fadeStart);
    _shader.setFloat(3, widget.fadeEnd);
  }

  ui.ImageFilter _createFilter() => ui.ImageFilter.compose(
        outer: ui.ImageFilter.shader(_shader),
        inner: ui.ImageFilter.blur(
          sigmaX: widget.sigma,
          sigmaY: widget.sigma,
          tileMode: ui.TileMode.clamp,
        ),
      );

  @override
  void dispose() {
    _shader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: _filter,
        child: const ColoredBox(color: Colors.transparent),
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
