import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Shared frosted/solid surface for floating navigation and action pills.
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
        final decoration = BoxDecoration(
          color: useGlass
              ? const Color(0xB8141416)
              : const Color(0xFF161618),
          borderRadius: radius,
          border: useGlass
              ? Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 0.8,
                  ),
                  left: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                )
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        );
        final surface = Container(decoration: decoration, child: child);

        if (!useGlass) {
          return ClipRRect(borderRadius: radius, child: surface);
        }

        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: surface,
          ),
        );
      },
    );
  }
}
