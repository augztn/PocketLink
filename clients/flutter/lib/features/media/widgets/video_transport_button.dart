import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/liquid_glass_pill.dart';

/// Compact smoked-glass transport control used by the video player.
class VideoTransportButton extends StatelessWidget {
  const VideoTransportButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 26,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: SmokedGlassSurface(
        radius: BorderRadius.circular(22),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          iconSize: iconSize,
          color: Colors.white,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
