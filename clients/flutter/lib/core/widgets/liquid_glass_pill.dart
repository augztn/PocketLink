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

        final decoration = useGlass
            ? BoxDecoration(
                gradient: LinearGradient(
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
                  filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: themedSurface,
                )
              : themedSurface,
        );

        return RepaintBoundary(child: clippedSurface);
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
