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
    this.intensity = 1,
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
        final level = intensity.clamp(0.0, 1.0).toDouble();
        if (level == 0) return const SizedBox.shrink();
        final useGlass = AppSettings.instance.useLiquidGlass;
        final useRefraction = useGlass && refractive;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = Theme.of(context).colorScheme;

        final decoration = useGlass
            ? BoxDecoration(
                color: useRefraction
                    ? (!isDark && lightRefractive
                        ? Colors.white.withValues(alpha: 0.58 * level)
                        : const Color(0xFF14151A).withValues(alpha: 0.55 * level))
                    : null,
                gradient: useRefraction ? null : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.14 * level),
                          Colors.white.withValues(alpha: 0.08 * level),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.85),
                          Colors.white.withValues(alpha: 0.72),
                        ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22 * level)
                      : const Color(0xFF94A3B8).withValues(alpha: 0.30 * level),
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
                  filter: ui.ImageFilter.blur(
                    sigmaX: (useRefraction ? 16 : 14) * level,
                    sigmaY: (useRefraction ? 16 : 14) * level,
                  ),
                  child: themedSurface,
                )
              : themedSurface,
        );

        final shadowedSurface = PhysicalShape(
          clipper: ShapeBorderClipper(
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
          color: Colors.transparent,
          elevation: useGlass ? 8 * level : 0,
          shadowColor: Colors.black.withValues(alpha: 0.22 * level),
          child: clippedSurface,
        );
        return useRefraction
            ? CustomPaint(
                foregroundPainter: _RefractiveGlassRimPainter(
                  radius: radius,
                  intensity: level,
                ),
                child: shadowedSurface,
              )
            : shadowedSurface;
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
    this.intensity = 1,
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
        final level = intensity.clamp(0.0, 1.0).toDouble();
        if (level == 0) return const SizedBox.shrink();
        final enabled = AppSettings.instance.useLiquidGlass;
        final isLight = Theme.of(context).brightness == Brightness.light;
        final borderColor = isLight
            ? const Color(0x1A0F172A)
            : Colors.white.withValues(alpha: 0.14);
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
        final glassChild = Theme(
          data: contentTheme,
          child: child,
        );
        final content = enabled
            ? Stack(
                fit: StackFit.passthrough,
                children: [
                  glassChild,
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
                                    Colors.white.withValues(alpha: 0.55 * level),
                                    Colors.white.withValues(alpha: 0.90 * level),
                                    Colors.white.withValues(alpha: 0.55 * level),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.02 * level),
                                    Colors.white.withValues(alpha: 0.42 * level),
                                    Colors.white.withValues(alpha: 0.02 * level),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : glassChild;
        final surface = ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: enabled
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: (refractive ? 16 : 14) * level,
                    sigmaY: (refractive ? 16 : 14) * level,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: refractive
                          ? const Color(0xFF14151A).withValues(alpha: 0.55 * level)
                          : isLight
                              ? Colors.white.withValues(alpha: 0.78 * level)
                              : const Color(0xFF1C1E24).withValues(alpha: 0.68 * level),
                      borderRadius: radius,
                      border: Border.all(
                        color: borderColor.withValues(alpha: borderColor.a * level),
                        width: 1,
                      ),
                    ),
                    child: content,
                  ),
                )
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
        final shadowedSurface = PhysicalShape(
          clipper: ShapeBorderClipper(
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
          color: Colors.transparent,
          elevation: enabled ? 8 * level : 0,
          shadowColor: Colors.black.withValues(alpha: 0.22 * level),
          child: surface,
        );
        return enabled && refractive
            ? CustomPaint(
                foregroundPainter: _RefractiveGlassRimPainter(
                  radius: radius,
                  intensity: level,
                ),
                child: shadowedSurface,
              )
            : shadowedSurface;
      },
    );
  }
}

class _RefractiveGlassRimPainter extends CustomPainter {
  const _RefractiveGlassRimPainter({
    required this.radius,
    this.intensity = 1,
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
      ..color = Colors.white.withValues(alpha: intensity)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.45 * intensity),
          Colors.white.withValues(alpha: 0.08 * intensity),
          Colors.white.withValues(alpha: 0.32 * intensity),
        ],
        stops: const [0, 0.52, 1],
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
    this.intensity = 1,
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
