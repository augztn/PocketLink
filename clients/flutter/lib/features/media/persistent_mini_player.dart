import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import 'persistent_audio_player.dart';

/// Compact representation of the app-scoped music session.
class PersistentMiniPlayer extends StatefulWidget {
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
  State<PersistentMiniPlayer> createState() => _PersistentMiniPlayerState();
}

class _PersistentMiniPlayerState extends State<PersistentMiniPlayer> {
  double _verticalDragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final item = widget.player.currentItem;
    if (item == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _verticalDragDistance = 0,
      onVerticalDragUpdate: (details) {
        _verticalDragDistance += details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final swipedUp =
            _verticalDragDistance < -24 || velocity < -250;
        _verticalDragDistance = 0;
        if (!widget.player.isPlaying && swipedUp) {
          widget.onDismiss();
        }
      },
      child: SolidPill(
        radius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onOpen,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.music_note_rounded,
                      color: colors.primary, size: 20),
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
                    tooltip: widget.player.isPlaying ? 'Pause' : 'Play',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.player.togglePlayback,
                    iconSize: 21,
                    color: colors.primary,
                    icon: Icon(widget.player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
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
