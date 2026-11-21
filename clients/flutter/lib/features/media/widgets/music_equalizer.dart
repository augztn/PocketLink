import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Animated playback indicator used by the media browser's music artwork.
class MusicEqualizer extends StatefulWidget {
  const MusicEqualizer({super.key});

  @override
  State<MusicEqualizer> createState() => _MusicEqualizerState();
}

class _MusicEqualizerState extends State<MusicEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 3,
                height: 5 +
                    12 *
                        (0.5 +
                            0.5 *
                                math.sin(
                                  (_controller.value * math.pi * 2) + i * 1.35,
                                )),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF536DFE),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      );
}
