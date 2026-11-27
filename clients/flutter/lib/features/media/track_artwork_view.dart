import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'discover/discover_thumbnail_cache.dart';

/// One artwork renderer shared by the mini-player, morph overlay and Now Playing.
class TrackArtworkView extends StatelessWidget {
  const TrackArtworkView({
    required this.fallbackColors,
    this.bytes,
    this.artworkUrl,
    this.fallbackIconSize = 30,
    this.borderRadius = BorderRadius.zero,
    this.fadeBottom = false,
    this.fadeBottomStart = 0.56,
    this.fit = BoxFit.cover,
    super.key,
  });

  final Uint8List? bytes;
  final String? artworkUrl;
  final List<Color> fallbackColors;
  final double fallbackIconSize;
  final BorderRadius borderRadius;
  final bool fadeBottom;
  final double fadeBottomStart;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fallbackColors[0].withValues(alpha: 0.92),
            fallbackColors[1].withValues(alpha: 0.78),
            fallbackColors[2],
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: fallbackIconSize,
          color: Colors.white,
        ),
      ),
    );

    final image = bytes != null && bytes!.isNotEmpty
        ? Image.memory(
            bytes!,
            cacheWidth: 544,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallback,
          )
        : artworkUrl?.isNotEmpty == true
            ? DiscoverThumbnail(
                url: DiscoverThumbnailCache.urlForSize(artworkUrl!, 544),
                cacheWidth: 544,
                fit: fit,
                fallback: fallback,
              )
            : fallback;

    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: fadeBottom
          ? ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, fadeBottomStart, 1],
              ).createShader(bounds),
              child: image,
            )
          : image,
    );
  }
}
