import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Shared optical-glass surface for PocketLink's floating controls.
///
/// The surface combines a clipped backdrop blur with the opaque smoked/milk
/// glass treatment used by the native reference. Keeping the fill opaque enough
/// preserves contrast over busy file lists and photo grids.
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

        final glassFill = isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.11),
                ],
                stops: const [0, 0.52, 1],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.82),
                  Colors.white.withValues(alpha: 0.62),
                  const Color(0xFFEEF2FF).withValues(alpha: 0.74),
                ],
                stops: const [0, 0.52, 1],
              );

        final border = useGlass
            ? isDark
                ? Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.50),
                      width: 1.2,
                    ),
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1.2,
                    ),
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 0.8,
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 0.8,
                    ),
                  )
                : Border.all(
                    color: const Color(0xFF94A3B8).withValues(alpha: 0.28),
                    width: 1,
                  )
            : Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.62),
                width: 1,
              );

        final decoration = BoxDecoration(
          color: useGlass ? null : colors.surfaceContainerLow,
          gradient: useGlass ? glassFill : null,
          borderRadius: radius,
          border: border,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: useGlass ? 0.45 : 0.10)
                  : const Color(0xFF0F172A)
                      .withValues(alpha: useGlass ? 0.08 : 0.07),
              blurRadius: useGlass ? (isDark ? 18 : 20) : 10,
              offset: useGlass
                  ? const Offset(0, 8)
                  : const Offset(0, 6),
              spreadRadius: useGlass ? 0 : -5,
            ),
          ],
        );

        final surface = DecoratedBox(
          decoration: decoration,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              if (useGlass)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.white.withValues(
                              alpha: isDark ? 0.075 : 0.95,
                            ),
                            Colors.transparent,
                          ],
                          stops: const [0, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              if (useGlass && !isDark)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.white.withValues(alpha: 0.45),
                            Colors.transparent,
                          ],
                          stops: const [0, 1],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
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
