import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// Shared top-edge blur and legibility surface for edge-to-edge screens.
class FeatheredGlassHeaderBackground extends StatelessWidget {
  const FeatheredGlassHeaderBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final settings = AppSettings.instance;
        final useProgressiveBlur =
            settings.progressiveBlurEnabled &&
            !settings.reduceDynamicBlur &&
            !media.disableAnimations;
        final headerHeight = media.padding.top + kToolbarHeight + 16;
        final statusBlurHeight = media.padding.top + 12;

        final tint = isDark
            ? const [
                Color(0xB8000000),
                Color(0x40000000),
                Colors.transparent,
              ]
            : const [
                Color(0xCCFFFFFF),
                Color(0x55FFFFFF),
                Colors.transparent,
              ];

        return SizedBox(
          width: double.infinity,
          height: headerHeight,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (useProgressiveBlur) ...[
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: statusBlurHeight,
                    child: ClipRect(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.68, 1.0],
                        ).createShader(bounds),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.55, 1.0],
                        ).createShader(bounds),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: tint,
                        stops: const [0.0, 0.48, 1.0],
                      ),
                    ),
                  ),
                ] else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          isDark
                              ? const Color(0xE6000000)
                              : const Color(0xF2FFFFFF),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
    return RepaintBoundary(
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              splashColor: foreground.withValues(alpha: 0.08),
              highlightColor: Colors.transparent,
              child: Tooltip(
                message: tooltip,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? const Color(0xFF1C1E24).withValues(alpha: 0.58)
                        : Colors.white.withValues(alpha: 0.58),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.24)
                          : const Color(0xFF94A3B8).withValues(alpha: 0.30),
                      width: 1.0,
                    ),
                  ),
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
        ),
      ),
    );
  }
}
