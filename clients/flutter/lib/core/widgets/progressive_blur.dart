import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Approximates a variable backdrop blur with eased, clipped blur bands.
///
/// Keep this widget inside a bounded Stack/ClipRect.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    this.maxSigma = 24,
    this.steps = 18,
    this.strongestAtBottom = false,
    super.key,
  });

  /// Blur sigma at the strongest edge.
  final double maxSigma;

  /// Number of grouped bands used to approximate progressive blur intensity.
  final int steps;

  /// When true, blur is strongest at the bottom instead of the top.
  final bool strongestAtBottom;

  /// Ease-in-out intensity matching BitChord's Haze progressive gradient.
  @visibleForTesting
  static double intensityAt(double distance) {
    final t = distance.clamp(0.0, 1.0).toDouble();
    return 1 - (t * t * (3 - 2 * t));
  }

  @override
  Widget build(BuildContext context) {
    if (!maxSigma.isFinite || maxSigma <= 0.1 ||
        steps < 1) {
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
          final sigma = maxSigma * intensityAt(distance);
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

        // Grouped filters share one backdrop capture instead of recapturing it.
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
