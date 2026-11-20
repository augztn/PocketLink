import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';

import 'liquid_glass_pill.dart';

/// Progressive blur surface used behind edge-to-edge browsing headers.
class FeatheredGlassHeaderBackground extends StatelessWidget {
  const FeatheredGlassHeaderBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Keep the page artwork and scroll content visible. This is only a soft
    // status-bar legibility fade, not a full-width blurred toolbar surface.
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [
                    Color(0x55000000),
                    Color(0x22000000),
                    Colors.transparent,
                  ]
                : const [
                    Color(0x66FFFFFF),
                    Color(0x22FFFFFF),
                    Colors.transparent,
                  ],
            stops: const [0, 0.48, 1],
          ),
        ),
      ),
    );
  }
}

/// Circular frosted action control for edge-to-edge headers.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({required this.tooltip, required this.onPressed, required this.child, this.size = 38, super.key});
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final double size;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF0F172A);
    return SizedBox.square(
      dimension: size,
      child: LiquidGlassSurface(
        radius: BorderRadius.circular(size / 2),
        refractive: true,
        lightRefractive: true,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            splashColor: foreground.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Tooltip(
              message: tooltip,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(color: foreground, size: 18),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
