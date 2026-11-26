import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'now_playing_artwork_palette.dart';
import 'track_artwork_view.dart';

/// Artwork surface used by the expanded Now Playing screen.
class NowPlayingArtworkCard extends StatelessWidget {
  const NowPlayingArtworkCard({
    required this.artwork,
    required this.artworkKey,
    required this.trackKey,
    required this.palette,
    required this.usesSharedArtwork,
    required this.artworkTargetKey,
    required this.artworkUrl,
    super.key,
  });

  final Uint8List? artwork;
  final String? artworkKey;
  final String trackKey;
  final List<Color> palette;
  final bool usesSharedArtwork;
  final GlobalKey? artworkTargetKey;
  final String? artworkUrl;

  @override
  Widget build(BuildContext context) {
    final hasArtwork = artwork != null && artworkKey == trackKey;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 40).clamp(0.0, 380.0).toDouble();
        final height = (constraints.maxHeight - 18).clamp(0.0, 380.0).toDouble();
        final dimension = math.min(width, height).clamp(0.0, 360.0).toDouble();
        return Container(
          key: artworkTargetKey,
          width: dimension,
          height: dimension,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: palette[0].withValues(alpha: 0.28),
                blurRadius: 38,
                spreadRadius: 2,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: usesSharedArtwork
              ? const SizedBox.expand()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    TrackArtworkView(
                      bytes: hasArtwork ? artwork : null,
                      artworkUrl: artworkUrl,
                      fallbackColors: palette,
                      fallbackIconSize: 92,
                    ),
                    if (hasArtwork)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.55, -0.7),
                            radius: 1.1,
                            colors: [
                              Colors.white.withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

}
