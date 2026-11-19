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
                  Color(0xCC252A36),
                  Color(0xB3191C25),
                  Color(0xC914161E),
                ],
                stops: [0, 0.48, 1],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xDFFFFFFF),
                  Color(0xCCEAF0FF),
                  Color(0xD4E6EBF8),
                ],
                stops: [0, 0.52, 1],
              );

        final border = useGlass
            ? Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.30 : 0.78),
                  width: isDark ? 1.0 : 1.15,
                ),
                left: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.54),
                ),
                right: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.48),
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
            color: useGlass ? null : colors.surfaceContainerLow,
            gradient: useGlass ? gradient : null,
            borderRadius: radius,
            border: border,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
                blurRadius: useGlass ? 30 : 18,
                offset: const Offset(0, 8),
                spreadRadius: -3,
              ),
              if (useGlass)
                BoxShadow(
                  color: (isDark ? Colors.black : const Color(0xFF283C8E))
                      .withValues(alpha: isDark ? 0.18 : 0.08),
                  blurRadius: 10,
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
                      Colors.white.withValues(alpha: isDark ? 0.14 : 0.46),
                      Colors.white.withValues(alpha: isDark ? 0.035 : 0.12),
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
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: surface,
            ),
          ),
        );
      },
    );
  }
}
