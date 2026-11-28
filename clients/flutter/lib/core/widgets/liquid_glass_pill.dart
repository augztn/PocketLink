import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Shared matte-frosted material for PocketLink floating surfaces.
/// Keep BackdropFilter directly in the clipped paint tree; never fade its
/// output through Opacity/AnimatedOpacity.
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
        final enabled = AppSettings.instance.useLiquidGlass;
        final value = intensity.clamp(0.0, 1.0).toDouble();
        if (value == 0) {
          return ClipRRect(borderRadius: radius, child: child);
        }
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final fill = isDark
            ? const Color(0xFF141518).withValues(alpha: 0.66 * value)
            : Colors.white.withValues(alpha: 0.68 * value);
        final decoration = BoxDecoration(
          color: enabled
              ? fill
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: radius,
        );
        final contentTheme = Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          iconButtonTheme: const IconButtonThemeData(
            style: ButtonStyle(
              overlayColor: WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
        );
        final material = Theme(
          data: contentTheme,
          child: DecoratedBox(decoration: decoration, child: child),
        );
        final blurSigma = AppSettings.instance.glassBlurStrength * value;
        final glassContent = enabled && blurSigma > 0
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                  tileMode: ui.TileMode.clamp,
                ),
                child: material,
              )
            : material;
        final clipped = ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: glassContent,
        );
        return enabled
            ? CustomPaint(
                foregroundPainter: _MatteGlassRimPainter(
                  radius: radius,
                  intensity: value,
                ),
                child: clipped,
              )
            : clipped;
      },
    );
  }
}

/// Matte frosted treatment for persistent floating surfaces such as the
/// mini-player. Disabling Liquid Glass fully unmounts its BackdropFilter.
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
    return LiquidGlassSurface(
      child: child,
      radius: radius,
      refractive: refractive,
      intensity: intensity,
    );
  }
}

class _MatteGlassRimPainter extends CustomPainter {
  const _MatteGlassRimPainter({
    required this.radius,
    this.intensity = 1.0,
  });

  final BorderRadius radius;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x23FFFFFF),
          Color(0x12FFFFFF),
          Color(0x0AFFFFFF),
        ],
        stops: [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawRRect(radius.toRRect(rect).deflate(0.5), paint..color = paint.color.withValues(alpha: intensity));
  }

  @override
  bool shouldRepaint(covariant _MatteGlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.intensity != intensity;
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
