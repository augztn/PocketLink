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
            return Image.memory(bytes, fit: fit, gaplessPlayback: true);
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
