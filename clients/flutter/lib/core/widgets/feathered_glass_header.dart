import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
import 'liquid_glass_pill.dart';
import 'pocketlink_scaffold.dart';

/// Shared top-edge blur and legibility surface for edge-to-edge screens.
class FeatheredGlassHeaderBackground extends StatelessWidget {
  const FeatheredGlassHeaderBackground({
    this.darkTint,
    this.contentHeight = kToolbarHeight,
    super.key,
  });

  final List<Color>? darkTint;
  final double contentHeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final settings = AppSettings.instance;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final useHeaderBlur = settings.progressiveBlurEnabled;
        // The AppBar includes a 32dp bottom fade extension. Keep the
        // filter bounded to that full region, then mask its lower edge to
        // transparent so the clip itself is never visible.
        const fadeExtension = 32.0;
        final headerHeight = media.padding.top + contentHeight + fadeExtension;

        final scrimColors = isDark
            ? const [
                Color(0xBF000000), // status bar: 75%
                Color(0xA6000000),
                Color(0x59000000), // title: 35%
                Color(0x33000000),
                Color(0x0F000000),
                Colors.transparent,
              ]
            : const [
                Color(0xBFFFFFFF),
                Color(0xA6FFFFFF),
                Color(0x59FFFFFF),
                Color(0x33FFFFFF),
                Color(0x0FFFFFFF),
                Colors.transparent,
              ];

        return LayoutBuilder(
          builder: (context, _) {
            if (TickerMode.of(context)) {
              LayoutInsetsScope.reportRenderedHeader(context, headerHeight);
            }

            return IgnorePointer(
              child: SizedBox(
                width: double.infinity,
                height: headerHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                      if (useHeaderBlur)
                        ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Color(0xA6FFFFFF),
                              Color(0x2EFFFFFF),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.58, 0.78, 0.90, 1.0],
                          ).createShader(bounds),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(
                              sigmaX: 14,
                              sigmaY: 14,
                            ),
                            child: const ColoredBox(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: scrimColors,
                            stops: const [0.0, 0.20, 0.48, 0.72, 0.88, 1.0],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Circular frosted action control for edge-to-edge headers.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.size = 38,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF0F172A);
    return LiquidGlassSurface(
      radius: BorderRadius.circular(size / 2),
      refractive: true,
      lightRefractive: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: size,
              height: size,
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
