import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final settings = AppSettings.instance;
        // Backdrop blur is a static rendering effect, not an animation.
        // Keep it available when the OS requests reduced motion.
        final useProgressiveBlur =
            settings.progressiveBlurEnabled &&
            settings.progressiveBlurStrength > 0;
        final blurScale = settings.progressiveBlurStrength / 55;
        final headerHeight = media.padding.top + contentHeight + 16;
        final statusBlurHeight = media.padding.top + 12;

        final tint = isDark
            ? (darkTint ?? const [
                Color(0xFF000000),
                Color(0xE6000000),
                Colors.transparent,
              ])
            : const [
                Color(0xCCFFFFFF),
                Color(0x55FFFFFF),
                Colors.transparent,
              ];

        return LayoutBuilder(
          builder: (context, _) {
            final renderedHeight = headerHeight;
            if (TickerMode.of(context)) {
              LayoutInsetsScope.reportRenderedHeader(context, renderedHeight);
            }
            return SizedBox(
          width: double.infinity,
          height: renderedHeight,
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
                          filter: ui.ImageFilter.blur(sigmaX: 24 * blurScale, sigmaY: 24 * blurScale),
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
                          filter: ui.ImageFilter.blur(sigmaX: 10 * blurScale, sigmaY: 10 * blurScale),
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
                        stops: const [0.0, 0.82, 1.0],
                      ),
                    ),
                  ),
                ] else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: darkTint != null && isDark
                            ? tint
                            : [
                                isDark
                                    ? const Color(0xFF000000)
                                    : const Color(0xF2FFFFFF),
                                isDark ? const Color(0xE6000000) : const Color(0xE6FFFFFF),
                                Colors.transparent,
                              ],
                        stops: darkTint != null && isDark
                            ? const [0.0, 0.82, 1.0]
                            : null,
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
    final settings = AppSettings.instance;
    final foreground = isDark ? Colors.white : const Color(0xFF0F172A);
    final button = CustomPaint(
      foregroundPainter: _GlassCircleRimPainter(isDark: isDark),
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
    );

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final useBlur = settings.progressiveBlurEnabled &&
            settings.progressiveBlurStrength > 0 &&
            !MediaQuery.of(context).disableAnimations;
        final blurScale = settings.progressiveBlurStrength / 55;
        return RepaintBoundary(
          child: ClipOval(
            child: useBlur
                ? BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24 * blurScale, sigmaY: 24 * blurScale),
                    child: button,
                  )
                : button,
          ),
        );
      },
    );
  }
}


class _GlassCircleRimPainter extends CustomPainter {
  const _GlassCircleRimPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = size.shortestSide;
    if (diameter <= 1) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [
                Color(0x99FFFFFF),
                Color(0x38FFFFFF),
                Color(0x08FFFFFF),
              ]
            : const [
                Color(0xAFFFFFFF),
                Color(0x54FFFFFF),
                Color(0x12FFFFFF),
              ],
        stops: const [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      diameter / 2 - 0.6,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassCircleRimPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
