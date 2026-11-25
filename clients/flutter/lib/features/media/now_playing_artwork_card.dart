import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'discover/discover_thumbnail_cache.dart';

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
              : AnimatedSwitcher(
                  duration: Duration.zero,
                  reverseDuration: Duration.zero,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                      child: child,
                    ),
                  ),
                  child: hasArtwork
                      ? Stack(
                          key: ValueKey(artworkKey),
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              artwork!,
                              cacheWidth: 544,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
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
                        )
                      : (artworkUrl?.isNotEmpty ?? false)
                          ? DiscoverThumbnail(
                              key: ValueKey('music-artwork-url:$artworkUrl'),
                              url: DiscoverThumbnailCache.urlForSize(artworkUrl!, 544),
                              cacheWidth: 544,
                              fallback: _fallback(),
                            )
                          : _fallback(key: const ValueKey('music-artwork-fallback')),
                ),
        );
      },
    );
  }

  Widget _fallback({Key? key}) => DecoratedBox(
        key: key,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette[0].withValues(alpha: 0.92),
              palette[1].withValues(alpha: 0.78),
              palette[2],
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.music_note_rounded, size: 92, color: Colors.white),
        ),
      );
}
