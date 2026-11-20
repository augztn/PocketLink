import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Shared optical-glass surface for PocketLink's floating controls.
///
/// The surface combines a clipped backdrop blur with a light translucent tint.
/// Keep the filter directly above the content it samples: no repaint boundary,
/// opacity, or fade transition may isolate the backdrop.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    required this.radius,
    this.refractive = false,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final useGlass = AppSettings.instance.useLiquidGlass || refractive;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = Theme.of(context).colorScheme;

        final decoration = useGlass
            ? BoxDecoration(
                color: refractive ? const Color(0xFF1A1C23).withValues(alpha: 0.40) : null,
                gradient: refractive ? null : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.white.withValues(alpha: 0.08),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.85),
                          Colors.white.withValues(alpha: 0.72),
                        ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFF94A3B8).withValues(alpha: 0.30),
                  width: 1,
                ),
              )
            : BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: radius,
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.62),
                  width: 1,
                ),
              );

        final surface = DecoratedBox(
          decoration: decoration,
          child: child,
        );

        final contentTheme = Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          iconButtonTheme: IconButtonThemeData(
            style: ButtonStyle(
              overlayColor: WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
        );
        final themedSurface = Theme(
          data: contentTheme,
          child: surface,
        );
        final clippedSurface = ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: useGlass
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: refractive ? 28 : 22, sigmaY: refractive ? 28 : 22),
                  child: themedSurface,
                )
              : themedSurface,
        );

        return RepaintBoundary(
          child: refractive
              ? CustomPaint(
                  foregroundPainter: _RefractiveGlassRimPainter(radius: radius),
                  child: clippedSurface,
                )
              : clippedSurface,
        );
      },
    );
  }
}


/// Always-on smoked glass treatment for the persistent mini-player.
///
/// Unlike the optional decorative glass surfaces, this keeps its backdrop blur
/// and translucent smoked tint active so page content remains visible beneath it.
class SmokedGlassSurface extends StatelessWidget {
  const SmokedGlassSurface({
    required this.child,
    required this.radius,
    this.refractive = false,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final borderColor = isLight
        ? const Color(0x1A0F172A)
        : Colors.white.withValues(alpha: 0.14);
    final surface = ClipRRect(
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: refractive ? 28 : 24, sigmaY: refractive ? 28 : 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: refractive
                ? const Color(0xFF1A1C23).withValues(alpha: 0.40)
                : isLight
                    ? Colors.white.withValues(alpha: 0.78)
                    : const Color(0xFF1C1E24).withValues(alpha: 0.68),
            borderRadius: radius,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: isLight
                ? const [BoxShadow(color: Color(0x140F172A), blurRadius: 18, offset: Offset(0, 5))]
                : const [],
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              Positioned(
                top: 0,
                left: 1,
                right: 1,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isLight
                            ? [
                                Colors.white.withValues(alpha: 0.55),
                                Colors.white.withValues(alpha: 0.90),
                                Colors.white.withValues(alpha: 0.55),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.02),
                                Colors.white.withValues(alpha: 0.42),
                                Colors.white.withValues(alpha: 0.02),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return refractive
        ? CustomPaint(
            foregroundPainter: _RefractiveGlassRimPainter(radius: radius),
            child: surface,
          )
        : surface;
  }
}

class _RefractiveGlassRimPainter extends CustomPainter {
  const _RefractiveGlassRimPainter({required this.radius});

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x73FFFFFF),
          Color(0x16FFFFFF),
          Color(0x52FFFFFF),
        ],
        stops: [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _RefractiveGlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

/// Backwards-compatible name retained for existing call sites.
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({
    required this.child,
    required this.radius,
    this.refractive = false,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;

  @override
  Widget build(BuildContext context) => LiquidGlassSurface(
        radius: radius,
        refractive: refractive,
        child: child,
      );
}
