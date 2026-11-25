import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'music_equalizer.dart';

/// Displays cached track artwork and the active-playback equalizer overlay.
class MusicArtwork extends StatelessWidget {
  const MusicArtwork({
    required this.future,
    this.playing = false,
    super.key,
  });

  final Future<Uint8List?> future;
  final bool playing;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF536DFE),
                      Color(0xFF7250C8),
                      Color(0xFF171827),
                    ],
                  ),
                ),
              ),
              FutureBuilder<Uint8List?>(
                future: future,
                builder: (context, snapshot) => snapshot.data == null
                    ? const Center(
                        child: Icon(
                          Icons.music_note_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                      )
                    : Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.music_note_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ),
              ),
              if (playing)
                const ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: MusicEqualizer()),
                ),
            ],
          ),
        ),
      );
}
