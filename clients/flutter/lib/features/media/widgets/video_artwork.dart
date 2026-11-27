import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

/// Loads and displays a video's thumbnail with the browser's fallback artwork.
class VideoArtwork extends StatelessWidget {
  const VideoArtwork({
    required this.future,
    required this.fit,
    super.key,
  });

  final Future<Uint8List?> future;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final pixelRatio = MediaQuery.devicePixelRatioOf(context);
                int? decodeSize(double logicalSize) {
                  if (!logicalSize.isFinite || logicalSize <= 0) return null;
                  return (logicalSize * pixelRatio).round().clamp(1, 960);
                }

                return Image.memory(
                  bytes,
                  cacheWidth: decodeSize(constraints.maxWidth),
                  cacheHeight: decodeSize(constraints.maxHeight),
                  fit: fit,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                );
              },
            );
          }
          final colors = Theme.of(context).colorScheme;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primaryContainer,
                  colors.surfaceContainerHighest,
                ],
              ),
            ),
            child: Icon(
              Icons.movie_creation_outlined,
              size: 42,
              color: colors.onSurfaceVariant,
            ),
          );
        },
      );
}
