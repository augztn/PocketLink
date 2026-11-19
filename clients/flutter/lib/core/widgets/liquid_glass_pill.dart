import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Reusable translucent glass surface shared by the dock, mini-player and
/// compact floating actions. Backdrop blur is only enabled when Liquid Glass
/// is enabled in Appearance settings.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    required this.radius,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final useGlass = AppSettings.instance.useLiquidGlass;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = Theme.of(context).colorScheme;

        final gradient = isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  Colors.white.withValues(alpha: 0.05),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB8FFFFFF),
                  Color(0x85EEF2FF),
                ],
              );

        final decoration = BoxDecoration(
          color: useGlass ? null : colors.surfaceContainerLow,
          gradient: useGlass ? gradient : null,
          borderRadius: radius,
          border: useGlass
              ? Border(
                  top: BorderSide(
                    color: Colors.white.withValues(
                      alpha: isDark ? 0.28 : 0.82,
                    ),
                    width: 1.1,
                  ),
                  left: BorderSide(
                    color: Colors.white.withValues(
                      alpha: isDark ? 0.13 : 0.58,
                    ),
                    width: 0.8,
                  ),
                  right: BorderSide(
                    color: Colors.white.withValues(
                      alpha: isDark ? 0.11 : 0.48,
                    ),
                    width: 0.8,
                  ),
                  bottom: BorderSide(
                    color: (isDark ? Colors.white : const Color(0xFF536DFE))
                        .withValues(alpha: isDark ? 0.07 : 0.16),
                    width: 0.8,
                  ),
                )
              : Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.62),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.07),
              blurRadius: useGlass ? 12 : 10,
              offset: const Offset(0, 4),
              spreadRadius: -4,
            ),
          ],
        );

        final surface = DecoratedBox(
          decoration: decoration,
          child: child,
        );

        if (!useGlass) {
          return ClipRRect(
            borderRadius: radius,
            child: surface,
          );
        }

        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: surface,
            ),
          ),
        );
      },
    );
  }
}

/// Backwards-compatible name retained for existing call sites.
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({
    required this.child,
    required this.radius,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => LiquidGlassSurface(
        radius: radius,
        child: child,
      );
}
