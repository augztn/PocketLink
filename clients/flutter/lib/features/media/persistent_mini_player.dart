import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
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

    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);

    var verticalDragDistance = 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => verticalDragDistance = 0,
      onVerticalDragUpdate: (details) => verticalDragDistance += details.delta.dy,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final swipedUp = verticalDragDistance < -24 || velocity < -250;
        if (!player.isPlaying && swipedUp) onDismiss();
      },
      child: SolidPill(
        radius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onOpen,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.music_note_rounded, color: colors.primary, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: player.player.stream.playing,
                    initialData: player.player.state.playing,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return IconButton(
                        tooltip: playing ? 'Pause' : 'Play',
                        visualDensity: VisualDensity.compact,
                        onPressed: player.togglePlayback,
                        iconSize: 21,
                        color: colors.primary,
                        icon: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        ),
                      );
                    },
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
