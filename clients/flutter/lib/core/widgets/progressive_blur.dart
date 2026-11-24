import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Applies a variable-strength backdrop blur across a bounded region.
///
/// The blur is strongest at one edge and falls away toward the opposite edge.
/// Use [strongestAtBottom] for surfaces behind the floating navigation dock.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    this.maxSigma = 22,
    this.steps = 14,
    this.exponent = 1.6,
    this.strongestAtBottom = false,
    super.key,
  });

  /// Blur sigma at the strongest edge.
  final double maxSigma;

  /// Number of clipped blur bands. 12–16 gives a smooth falloff.
  final int steps;

  /// Falloff curve. Values above 1 concentrate blur near the strong edge.
  final double exponent;

  /// When true, the strongest band is placed at the bottom edge.
  final bool strongestAtBottom;

  @override
  Widget build(BuildContext context) {
    if (!maxSigma.isFinite ||
        maxSigma <= 0.1 ||
        steps < 1 ||
        !exponent.isFinite ||
        exponent <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (!height.isFinite || height <= 0) {
          return const SizedBox.shrink();
        }

        final bandHeight = height / steps;
        final bands = <Widget>[];

        for (var index = 0; index < steps; index++) {
          final distance = (index + 0.5) / steps;
          final sigma =
              maxSigma * math.pow(1 - distance, exponent).toDouble();
          if (sigma < 0.4) continue;

          final top = strongestAtBottom
              ? height - (index + 1) * bandHeight
              : index * bandHeight;

          bands.add(
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: bandHeight,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: bands,
        );
      },
    );
  }
}
