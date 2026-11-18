import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import 'persistent_audio_player.dart';

/// Compact representation of the app-scoped music session.
class PersistentMiniPlayer extends StatelessWidget {
  const PersistentMiniPlayer({
    required this.player,
    required this.onOpen,
    super.key,
  });

  final PersistentAudioPlayer player;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);

    return SolidPill(
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
                IconButton(
                  tooltip: player.isPlaying ? 'Pause' : 'Play',
                  visualDensity: VisualDensity.compact,
                  onPressed: player.togglePlayback,
                  iconSize: 21,
                  color: colors.primary,
                  icon: Icon(player.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
