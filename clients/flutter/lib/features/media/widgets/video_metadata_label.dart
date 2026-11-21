import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';

/// Displays available video resolution and duration metadata.
class VideoMetadataLabel extends StatelessWidget {
  const VideoMetadataLabel({
    required this.future,
    required this.formatDuration,
    super.key,
  });

  final Future<VideoMetadata?> future;
  final String Function(int milliseconds) formatDuration;

  @override
  Widget build(BuildContext context) => FutureBuilder<VideoMetadata?>(
        future: future,
        builder: (context, snapshot) {
          final metadata = snapshot.data;
          if (metadata == null) return const SizedBox.shrink();
          final parts = <String>[
            if (metadata.resolution.isNotEmpty) metadata.resolution,
            if (metadata.durationMs > 0) formatDuration(metadata.durationMs),
          ];
          if (parts.isEmpty) return const SizedBox.shrink();
          return Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      );
}
