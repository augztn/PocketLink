import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
import 'pocketlink_scaffold.dart';

final Future<ui.FragmentProgram> _progressiveBlurProgram =
    ui.FragmentProgram.fromAsset('shaders/progressive_blur.frag');

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
        final blurScale = settings.progressiveBlurStrength / 55;
        final useBlur = settings.progressiveBlurEnabled &&
            settings.progressiveBlurStrength > 0 &&
            _isScrolled;
        final headerHeight =
            media.padding.top + widget.contentHeight + pocketLinkHeaderFadeTailHeight;
        final scrimBase = theme.scaffoldBackgroundColor;
        final scrimColors = [
          scrimBase.withValues(alpha: isDark ? 0.78 : 0.78),
          scrimBase.withValues(alpha: 0.45),
          scrimBase.withValues(alpha: 0.12),
          Colors.transparent,
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
                      devicePixelRatio: media.devicePixelRatio,
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: scrimColors,
                            stops: const [0, 0.55, 0.85, 1],
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

  Widget _buildProgressiveBlur({
    required double height,
    required double blurScale,
    required double devicePixelRatio,
  }) {
    final fallback = _buildSteppedBlur(height: height, blurScale: blurScale);
    if (!ui.ImageFilter.isShaderFilterSupported) return fallback;

    return FutureBuilder<ui.FragmentProgram>(
      future: _progressiveBlurProgram,
      builder: (context, snapshot) {
        final program = snapshot.data;
        if (program == null) return fallback;
        return _ProgressiveShaderBackdropFilter(
          program: program,
          maxSigma: 18 * blurScale * devicePixelRatio,
          minSigma: 1.2 * blurScale * devicePixelRatio,
        );
      },
    );
  }

  Widget _buildSteppedBlur({
    required double height,
    required double blurScale,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _blurBand(top: 0, bottom: 0.35, height: height, sigma: 18 * blurScale),
        _blurBand(top: 0.35, bottom: 0.55, height: height, sigma: 12 * blurScale),
        _blurBand(top: 0.55, bottom: 0.72, height: height, sigma: 7 * blurScale),
        _blurBand(top: 0.72, bottom: 0.86, height: height, sigma: 3.5 * blurScale),
        _blurBand(top: 0.86, bottom: 1, height: height, sigma: 1.2 * blurScale),
      ],
    );
  }
}

/// Single-pass variable-radius backdrop blur for Impeller-capable renderers.
/// The stepped implementation remains the compatibility path on other backends.
class _ProgressiveShaderBackdropFilter extends StatefulWidget {
  const _ProgressiveShaderBackdropFilter({
    required this.program,
    required this.maxSigma,
    required this.minSigma,
  });

  final ui.FragmentProgram program;
  final double maxSigma;
  final double minSigma;

  @override
  State<_ProgressiveShaderBackdropFilter> createState() =>
      _ProgressiveShaderBackdropFilterState();
}

class _ProgressiveShaderBackdropFilterState
    extends State<_ProgressiveShaderBackdropFilter> {
  late final ui.FragmentShader _shader;
  late final ui.ImageFilter _filter;

  @override
  void initState() {
    super.initState();
    _shader = widget.program.fragmentShader();
    _updateUniforms();
    _filter = ui.ImageFilter.shader(_shader);
  }

  @override
  void didUpdateWidget(covariant _ProgressiveShaderBackdropFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxSigma != widget.maxSigma ||
        oldWidget.minSigma != widget.minSigma) {
      _updateUniforms();
    }
  }

  void _updateUniforms() {
    _shader.setFloat(2, widget.maxSigma);
    _shader.setFloat(3, widget.minSigma);
  }

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

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final useBlur = settings.progressiveBlurEnabled &&
            settings.progressiveBlurStrength > 0 &&
            !MediaQuery.of(context).disableAnimations;
        final blurScale = settings.progressiveBlurStrength / 55;
        return RepaintBoundary(
          child: ClipOval(
            child: useBlur
                ? BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24 * blurScale, sigmaY: 24 * blurScale),
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
