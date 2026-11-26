import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Approximates a variable backdrop blur with clipped, stepped blur bands.
///
/// Keep this widget inside a bounded Stack/ClipRect and do not put an
/// Opacity, FadeTransition or ShaderMask above it.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    this.maxSigma = 24,
    this.steps = 14,
    this.exponent = 1.6,
    this.strongestAtBottom = false,
    super.key,
  });

  /// Blur sigma at the strongest edge.
  final double maxSigma;

  /// Number of clipped bands used to approximate the blur falloff.
  final int steps;

  /// Falloff exponent. Values above 1 concentrate blur near the strong edge.
  final double exponent;

  /// When true, blur is strongest at the bottom instead of the top.
  final bool strongestAtBottom;

  @override
  Widget build(BuildContext context) {
    if (!maxSigma.isFinite || maxSigma <= 0.1 ||
        steps < 1 || !exponent.isFinite || exponent <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (!height.isFinite || height <= 0) {
          return const SizedBox.shrink();
        }

        final reportedDpr = MediaQuery.of(context).devicePixelRatio;
        final devicePixelRatio =
            reportedDpr.isFinite && reportedDpr > 0 ? reportedDpr : 1.0;
        final onePhysicalPixel = 1 / devicePixelRatio;
        double snap(double value) =>
            (value * devicePixelRatio).roundToDouble() / devicePixelRatio;

        final bands = <Widget>[];
        for (var index = 0; index < steps; index++) {
          final distance = (index + 0.5) / steps;
          final sigma = maxSigma * math.pow(1 - distance, exponent).toDouble();
          if (sigma < 0.1) continue;

          final startFraction = strongestAtBottom
              ? (steps - index - 1) / steps
              : index / steps;
          final endFraction = strongestAtBottom
              ? (steps - index) / steps
              : (index + 1) / steps;
          final top = snap(height * startFraction);
          final baseBottom = snap(height * endFraction);
          final isLastBand = strongestAtBottom
              ? index == 0
              : index == steps - 1;
          // Extend each internal edge by one physical pixel. Grouped filters
          // share the original backdrop, so this overlap closes raster gaps
          // without applying one band's blur on top of its neighbour.
          final bottom = isLastBand
              ? height
              : math.min(height, baseBottom + onePhysicalPixel).toDouble();
          if (bottom <= top) continue;

          bands.add(
            Positioned(
              top: top,
              left: 0,
              right: 0,
              height: bottom - top,
              child: ClipRect(
                child: BackdropFilter.grouped(
                  filter: ui.ImageFilter.blur(
                    sigmaX: sigma,
                    sigmaY: sigma,
                  ),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ),
          );
        }

        // All bands sample the same backdrop. Grouping lets the engine share
        // the backdrop input instead of capturing it independently per band.
        return BackdropGroup(
          child: Stack(
            fit: StackFit.expand,
            children: bands,
          ),
        );
      },
    );
  }
}
