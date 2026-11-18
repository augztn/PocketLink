import 'package:material_ui/material_ui.dart';

import 'persistent_audio_player.dart';

class PersistentMiniPlayer extends StatelessWidget {
  const PersistentMiniPlayer({
    required this.player,
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });

  final PersistentAudioPlayer player;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (!player.isPlaying && velocity > 300) onDismiss();
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(Icons.music_note_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'NOW PLAYING',
                          style: TextStyle(fontSize: 9, letterSpacing: 1.1),
                        ),
                      ],
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: player.player.stream.playing,
                    initialData: player.player.state.playing,
                    builder: (context, snapshot) => IconButton(
                      tooltip: (snapshot.data ?? false) ? 'Pause' : 'Play',
                      onPressed: player.togglePlayback,
                      icon: Icon(
                        (snapshot.data ?? false)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next track',
                    onPressed: player.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
