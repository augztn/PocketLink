import 'package:flutter/material.dart';

class MusicDurationLabel extends StatelessWidget {
  const MusicDurationLabel({
    required this.future,
    required this.formatDuration,
    super.key,
  });

  final Future<int> future;
  final String Function(int milliseconds) formatDuration;

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: future,
        builder: (context, snapshot) {
          final durationMs = snapshot.data ?? 0;
          if (durationMs <= 0) return const SizedBox.shrink();
          return Text(
            formatDuration(durationMs),
            style: const TextStyle(
              color: Color(0xFF8E939E),
              fontSize: 12.5,
              fontFamily: 'JetBrains Mono',
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          );
        },
      );
}
