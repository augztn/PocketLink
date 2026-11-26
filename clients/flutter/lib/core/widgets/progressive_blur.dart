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
    this.endSigma = 24,
    this.strongestAtBottom = false,
    super.key,
  });

  /// Blur sigma at the strongest edge, in logical pixels.
  final double maxSigma;

  /// Blur sigma at the feathered edge, in logical pixels. Set equal to
  /// [maxSigma] for a uniform blur that is faded with an alpha mask.
  final double endSigma;

  /// When true, blur is strongest at the bottom instead of the top.
  final bool strongestAtBottom;

  @override
  Widget build(BuildContext context) {
    if (!maxSigma.isFinite || maxSigma <= 0 || !endSigma.isFinite) {
      return const SizedBox.shrink();
    }

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final maxSigmaPhysical = maxSigma * pixelRatio;
    final endSigmaPhysical = endSigma * pixelRatio;

    return shader_blur.ProgressiveBlur(
      begin: strongestAtBottom
          ? Alignment.bottomCenter
          : Alignment.topCenter,
      end: strongestAtBottom
          ? Alignment.topCenter
          : Alignment.bottomCenter,
      sigmaStart: maxSigmaPhysical
          .clamp(0.0, shader_blur.ProgressiveBlur.maxSigma)
          .toDouble(),
      sigmaEnd: endSigmaPhysical
          .clamp(0.0, shader_blur.ProgressiveBlur.maxSigma)
          .toDouble(),
      child: const SizedBox.expand(),
    );
  }
}
