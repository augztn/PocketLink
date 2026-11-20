import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';

/// Progressive blur surface used behind edge-to-edge browsing headers.
class FeatheredGlassHeaderBackground extends StatelessWidget {
  const FeatheredGlassHeaderBackground({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final legibility = isDark
        ? const [Color(0xC8000000), Color(0x55000000), Colors.transparent]
        : const [Color(0xD8FFFFFF), Color(0x66FFFFFF), Colors.transparent];
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.58, 1.0],
        ).createShader(bounds),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: const ColoredBox(color: Colors.transparent),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: legibility,
                  stops: const [0.0, 0.58, 1.0],
                ),
              ),
            ),
          ],
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
    return RepaintBoundary(child: ClipOval(child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Material(color: Colors.transparent, child: InkWell(
        onTap: onPressed, customBorder: const CircleBorder(),
        splashColor: foreground.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Tooltip(message: tooltip, child: Container(
          width: size, height: size, alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? const Color(0xFF1C1E24).withValues(alpha: 0.58)
                : Colors.white.withValues(alpha: 0.58),
            border: Border.all(color: isDark
              ? Colors.white.withValues(alpha: 0.24)
              : const Color(0xFF94A3B8).withValues(alpha: 0.30)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: IconTheme(
                  data: IconThemeData(color: foreground, size: 18),
                  child: child,
                ),
              ),
              Positioned(
                top: 0,
                left: size * 0.22,
                right: size * 0.22,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.02),
                          Colors.white.withValues(alpha: isDark ? 0.42 : 0.86),
                          Colors.white.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        )),
      )),
    )));
  }
}
