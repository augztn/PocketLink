import 'package:material_ui/material_ui.dart';
import 'package:progressive_background_blur/progressive_background_blur.dart'
    as shader_blur;

/// Continuous shader-based backdrop blur with a vertical sigma gradient.
///
/// Unlike clipped blur bands, the fragment shader interpolates blur strength
/// per pixel, so there are no horizontal layer boundaries.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    this.maxSigma = 24,
    this.strongestAtBottom = false,
    super.key,
  });

  /// Blur sigma at the strongest edge.
  final double maxSigma;

  /// When true, blur is strongest at the bottom instead of the top.
  final bool strongestAtBottom;

  @override
  Widget build(BuildContext context) {
    if (!maxSigma.isFinite || maxSigma <= 0) {
      return const SizedBox.shrink();
    }

    return shader_blur.ProgressiveBlur(
      begin: strongestAtBottom
          ? Alignment.bottomCenter
          : Alignment.topCenter,
      end: strongestAtBottom
          ? Alignment.topCenter
          : Alignment.bottomCenter,
      sigmaStart: maxSigma
          .clamp(0.0, shader_blur.ProgressiveBlur.maxSigma)
          .toDouble(),
      sigmaEnd: 0,
      child: const SizedBox.expand(),
    );
  }
}
