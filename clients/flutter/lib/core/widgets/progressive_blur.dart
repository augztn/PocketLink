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

        final bandHeight = height / steps;
        final bands = <Widget>[];
        for (var index = 0; index < steps; index++) {
          final distance = (index + 0.5) / steps;
          final sigma = maxSigma * math.pow(1 - distance, exponent);
          if (sigma < 0.4) continue;

          final top = strongestAtBottom
              ? height - (index + 1) * bandHeight
              : index * bandHeight;
          bands.add(
            Positioned(
              top: top,
              left: 0,
              right: 0,
              height: bandHeight + 1,
              child: ClipRect(
                child: BackdropFilter(
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

        return Stack(
          fit: StackFit.expand,
          children: bands,
        );
      },
    );
  }
}
