import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';
import 'video_tag.dart';

/// Displays a video's duration as a compact thumbnail badge.
class VideoDurationBadge extends StatelessWidget {
  const VideoDurationBadge({
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
          final duration = snapshot.data?.durationMs ?? 0;
          if (duration <= 0) return const SizedBox.shrink();
          return VideoTag(label: formatDuration(duration));
        },
      );
}
