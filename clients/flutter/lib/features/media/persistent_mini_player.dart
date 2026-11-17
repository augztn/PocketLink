import 'package:material_ui/material_ui.dart';

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

        return Material(
          color: const Color(0xFF211A35),
          elevation: 12,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.album_rounded, color: Color(0xFFD8C9FF), size: 34),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'PocketLink • Now playing',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
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
                    color: Colors.white70,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    tooltip: playback.isPlaying ? 'Pause' : 'Play',
                    onPressed: playback.togglePlayback,
                    color: const Color(0xFFD8C9FF),
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
                    color: Colors.white54,
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
