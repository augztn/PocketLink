import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import 'media_player_screen.dart';
import 'persistent_audio_player.dart';

class PersistentMiniPlayer extends StatelessWidget {
  const PersistentMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playback = PersistentAudioPlayer.instance;
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final track = playback.currentItem;
        final api = playback.api;
        if (!playback.showMiniPlayer || track == null || api == null) {
          return const SizedBox.shrink();
        }

        final isLight = Theme.of(context).brightness == Brightness.light;
        final foreground = isLight ? const Color(0xFF0F172A) : Colors.white;
        final secondary = isLight ? const Color(0xFF475569) : Colors.white70;
        return SmokedGlassSurface(
          radius: BorderRadius.circular(18),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.album_rounded, color: Theme.of(context).colorScheme.primary, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MediaPlayerScreen(
                            api: api,
                            title: track.title,
                            path: track.path,
                            volume: track.volume,
                            isVideo: false,
                            queue: playback.queue,
                            initialIndex: playback.currentIndex,
                            resumeExisting: true,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title.replaceAll(RegExp(r'\\.[^.]+$'), ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'PocketLink • Now playing',
                              style: TextStyle(
                                color: secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous track',
                    onPressed: playback.queue.length > 1
                        ? playback.player.previous
                        : null,
                    color: secondary,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    tooltip: playback.isPlaying ? 'Pause' : 'Play',
                    onPressed: playback.togglePlayback,
                    color: foreground,
                    icon: Icon(
                      playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next track',
                    onPressed: playback.queue.length > 1
                        ? playback.player.next
                        : null,
                    color: Colors.white70,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close player',
                    onPressed: playback.dismiss,
                    color: secondary.withValues(alpha: 0.7),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
