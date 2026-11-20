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
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final bool refractive;
  final bool lightRefractive;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final useGlass = AppSettings.instance.useLiquidGlass || refractive;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = Theme.of(context).colorScheme;
        final optical = useGlass;
        final decoration = useGlass
            ? BoxDecoration(
                color: optical
                    ? (!isDark && lightRefractive
                        ? Colors.white.withValues(alpha: 0.56)
                        : const Color(0xFF16181F).withValues(alpha: 0.44))
                    : null,
                gradient: optical
                    ? null
                    : LinearGradient(
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
        final surface = ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: useGlass
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: optical ? 28 : 22,
                    sigmaY: optical ? 28 : 22,
                  ),
                  child: DecoratedBox(
                    decoration: decoration,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        Theme(data: contentTheme, child: child),
                        if (optical)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: isDark
                                        ? [
                                            Colors.white.withValues(alpha: 0.11),
                                            Colors.transparent,
                                            Colors.white.withValues(alpha: 0.05),
                                          ]
                                        : [
                                            Colors.white.withValues(alpha: 0.35),
                                            Colors.transparent,
                                            Colors.white.withValues(alpha: 0.18),
                                          ],
                                    stops: const [0, 0.52, 1],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: decoration,
                    child: Theme(data: contentTheme, child: child),
                  ),
                ),
        );
        final polishedSurface = optical
            ? CustomPaint(
                foregroundPainter: _RefractiveGlassRimPainter(
                  radius: radius,
                  isDark: isDark,
                ),
                child: surface,
              )
            : surface;

        return Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: useGlass
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: polishedSurface,
        );
      },
    );
  }
}

/// Shared floating smoked-glass surface used by the persistent mini-player.
/// The Appearance setting switches between the classic smoked treatment and
/// the higher-translucency optical lens treatment without changing layout.
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
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        final optical = AppSettings.instance.useLiquidGlass || refractive;
        final borderColor = isLight
            ? const Color(0x1A0F172A)
            : Colors.white.withValues(alpha: 0.14);
        final surface = ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: optical ? 28 : 24,
              sigmaY: optical ? 28 : 24,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: optical
                    ? isLight
                        ? Colors.white.withValues(alpha: 0.56)
                        : const Color(0xFF16181F).withValues(alpha: 0.44)
                    : isLight
                        ? Colors.white.withValues(alpha: 0.78)
                        : const Color(0xFF1C1E24).withValues(alpha: 0.68),
                borderRadius: radius,
                border: Border.all(
                  color: optical
                      ? (isLight
                          ? Colors.white.withValues(alpha: 0.70)
                          : Colors.white.withValues(alpha: 0.18))
                      : borderColor,
                  width: 1,
                ),
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  child,
                  if (optical)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isLight
                                  ? [
                                      Colors.white.withValues(alpha: 0.35),
                                      Colors.transparent,
                                      Colors.white.withValues(alpha: 0.18),
                                    ]
                                  : [
                                      Colors.white.withValues(alpha: 0.11),
                                      Colors.transparent,
                                      Colors.white.withValues(alpha: 0.05),
                                    ],
                              stops: const [0, 0.52, 1],
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
        final polishedSurface = optical
            ? CustomPaint(
                foregroundPainter: _RefractiveGlassRimPainter(
                  radius: radius,
                  isDark: !isLight,
                ),
                child: surface,
              )
            : surface;
        return Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: optical ? 0.35 : 0.12),
                blurRadius: optical ? 20 : 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: polishedSurface,
        );
      },
    );
  }
}

class _RefractiveGlassRimPainter extends CustomPainter {
  const _RefractiveGlassRimPainter({
    required this.radius,
    required this.isDark,
  });

  final BorderRadius radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.62);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [
                Color(0x73FFFFFF),
                Color(0x1AFFFFFF),
                Color(0x47FFFFFF),
              ]
            : const [
                Color(0xB3FFFFFF),
                Color(0x2694A3B8),
                Color(0x80FFFFFF),
              ],
        stops: const [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _RefractiveGlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.isDark != isDark;
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
