import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Shared liquid-glass surface for floating navigation and compact actions.
///
/// Blur is applied behind the clipped surface; layered gradients and a fine
/// specular rim preserve contrast without making the content underneath noisy.
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({
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
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xEE252A36),
                  Color(0xE6191C25),
                  Color(0xF414161E),
                ],
                stops: [0, 0.48, 1],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xF8FFFFFF),
                  Color(0xEEF2F5FF),
                  Color(0xF3EAF0FF),
                ],
                stops: [0, 0.52, 1],
              );

        final border = useGlass
            ? Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.92),
                  width: isDark ? 1.0 : 1.2,
                ),
                left: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.13 : 0.72),
                ),
                right: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.72),
                ),
                bottom: BorderSide(
                  color: (isDark ? Colors.white : const Color(0xFF4760FA))
                      .withValues(alpha: isDark ? 0.10 : 0.15),
                ),
              )
            : Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.62),
                width: 1,
              );

        final surface = Container(
          decoration: BoxDecoration(
            color: useGlass
                ? null
                : (isDark
                    ? const Color(0xFF161618)
                    : colors.surface),
            gradient: useGlass ? gradient : null,
            borderRadius: radius,
            border: border,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.12),
                blurRadius: useGlass ? 26 : 18,
                offset: const Offset(0, 8),
                spreadRadius: -3,
              ),
              if (useGlass)
                BoxShadow(
                  color: (isDark ? Colors.black : const Color(0xFF283C8E))
                      .withValues(alpha: isDark ? 0.18 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            gradient: useGlass
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.42, 1],
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.10 : 0.62),
                      Colors.white.withValues(alpha: isDark ? 0.025 : 0.10),
                      Colors.transparent,
                    ],
                  )
                : null,
          ),
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
