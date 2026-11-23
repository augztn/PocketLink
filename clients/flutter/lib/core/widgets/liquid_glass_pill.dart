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
    this.lightRefractive = false,
    this.intensity = 1.0,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;
  final bool lightRefractive;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final useGlass = AppSettings.instance.useLiquidGlass;
        final useRefraction = useGlass && refractive;
        final glassIntensity = intensity.clamp(0.0, 1.0).toDouble();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = Theme.of(context).colorScheme;

        final decoration = useGlass
            ? BoxDecoration(
                color: useRefraction
                    ? (!isDark && lightRefractive
                        ? Colors.white.withValues(alpha: 0.58 * glassIntensity)
                        : const Color(0xFF1A1C23).withValues(alpha: 0.40 * glassIntensity))
                    : null,
                gradient: useRefraction ? null : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.14 * glassIntensity),
                          Colors.white.withValues(alpha: 0.08 * glassIntensity),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.85 * glassIntensity),
                          Colors.white.withValues(alpha: 0.72 * glassIntensity),
                        ],
                ),
                borderRadius: radius,
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
          child: useGlass && glassIntensity > 0
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: (useRefraction ? 28 : 22) * glassIntensity,
                    sigmaY: (useRefraction ? 28 : 22) * glassIntensity,
                  ),
                  child: themedSurface,
                )
              : themedSurface,
        );

        return useGlass && glassIntensity > 0
            ? CustomPaint(
                foregroundPainter: _RefractiveGlassRimPainter(
                  radius: radius,
                  intensity: glassIntensity,
                ),
                child: clippedSurface,
              )
            : RepaintBoundary(child: clippedSurface);
      },
    );
  }
}


/// Optional smoked-glass treatment for persistent floating surfaces.
class SmokedGlassSurface extends StatelessWidget {
  const SmokedGlassSurface({
    required this.child,
    required this.radius,
    this.refractive = false,
    this.intensity = 1.0,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final enabled = AppSettings.instance.useLiquidGlass;
        final glassIntensity = intensity.clamp(0.0, 1.0).toDouble();
        final isLight = Theme.of(context).brightness == Brightness.light;
        final content = enabled
            ? Stack(
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
                                    Colors.white.withValues(alpha: 0.55 * glassIntensity),
                                    Colors.white.withValues(alpha: 0.90 * glassIntensity),
                                    Colors.white.withValues(alpha: 0.55 * glassIntensity),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.02 * glassIntensity),
                                    Colors.white.withValues(alpha: 0.42 * glassIntensity),
                                    Colors.white.withValues(alpha: 0.02 * glassIntensity),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : child;
        final glassDecoration = DecoratedBox(
          decoration: BoxDecoration(
            color: refractive
                ? const Color(0xFF1A1C23).withValues(alpha: 0.40 * glassIntensity)
                : isLight
                    ? Colors.white.withValues(alpha: 0.78 * glassIntensity)
                    : const Color(0xFF1C1E24).withValues(alpha: 0.68 * glassIntensity),
            borderRadius: radius,
            boxShadow: isLight
                ? const [
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 18,
                      offset: Offset(0, 5),
                    ),
                  ]
                : const [],
          ),
          child: content,
        );
        final surface = ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: enabled && glassIntensity > 0
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: (refractive ? 28 : 24) * glassIntensity,
                    sigmaY: (refractive ? 28 : 24) * glassIntensity,
                  ),
                  child: glassDecoration,
                )
              : enabled
                  ? child
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: radius,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: child,
                    ),
        );
        return enabled && glassIntensity > 0
            ? CustomPaint(
                foregroundPainter: _RefractiveGlassRimPainter(
                  radius: radius,
                  intensity: glassIntensity,
                ),
                child: surface,
              )
            : surface;
      },
    );
  }
}

class _RefractiveGlassRimPainter extends CustomPainter {
  const _RefractiveGlassRimPainter({
    required this.radius,
    this.intensity = 1.0,
  });

  final BorderRadius radius;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.28 * intensity),
          Colors.white.withValues(alpha: 0.10 * intensity),
          Colors.white.withValues(alpha: 0.05 * intensity),
        ],
        stops: const [0, 0.48, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _RefractiveGlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.intensity != intensity;
}

/// Backwards-compatible name retained for existing call sites.
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({
    required this.child,
    required this.radius,
    this.refractive = false,
    this.intensity = 1.0,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;
  final double intensity;

  @override
  Widget build(BuildContext context) => LiquidGlassSurface(
        radius: radius,
        refractive: refractive,
        intensity: intensity,
        child: child,
      );
}
