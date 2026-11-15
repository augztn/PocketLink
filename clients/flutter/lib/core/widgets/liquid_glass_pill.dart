import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
          border: Border.all(
            color: Colors.white.withValues(alpha: useGlass ? 0.16 : 0.08),
            width: useGlass ? 0.8 : 1,
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
