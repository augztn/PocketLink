import 'package:flutter/material.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/home_server_app_bar.dart';

class NowPlayingSettingsScreen extends StatelessWidget {
  const NowPlayingSettingsScreen({super.key});

  Widget _section(String title, List<Widget> children) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
      ...children,
    ]),
  );

  Widget _setting(String title, String subtitle, IconData icon, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(secondary: Icon(icon), title: Text(title), subtitle: Text(subtitle),
        value: value, onChanged: onChanged);

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Scaffold(
        appBar: HomeServerAppBar(title: const Text('Now Playing')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _section('General layout', [
                SwitchListTile(
                  secondary: const Icon(Icons.picture_in_picture_alt_rounded),
                  title: const Text('Mini-player'),
                  subtitle: const Text('Show the compact player above the navigation dock while music is playing'),
                  value: settings.showMiniPlayer,
                  onChanged: (value) => settings.setNowPlayingOptions(miniPlayer: value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.album_rounded),
                  title: const Text('Artwork'),
                  subtitle: const Text('Show album artwork on the full player'),
                  value: settings.showNowPlayingArtwork,
                  onChanged: (value) => settings.setNowPlayingOptions(artwork: value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: const Text('Volume control'),
                  subtitle: const Text('Show the in-player volume slider'),
                  value: settings.showNowPlayingVolume,
                  onChanged: (value) => settings.setNowPlayingOptions(volume: value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.tune_rounded),
                  title: const Text('Extra playback controls'),
                  subtitle: const Text('Show shuffle, repeat and queue shortcuts'),
                  value: settings.showNowPlayingUtilities,
                  onChanged: (value) => settings.setNowPlayingOptions(utilities: value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe_rounded),
                  title: const Text('Swipe gestures'),
                  subtitle: const Text('Swipe down to close; swipe left or right to change tracks'),
                  value: settings.enableNowPlayingGestures,
                  onChanged: (value) => settings.setNowPlayingOptions(gestures: value),
                ),
            ]),
            const SizedBox(height: 12),
            _section('Track information', [
              _setting('File format', 'Show the audio format label', Icons.audio_file_rounded, settings.showNowPlayingFormat, (v) => settings.setNowPlayingOptions(format: v)),
              _setting('Track title', 'Show the current track name', Icons.title_rounded, settings.showNowPlayingTitle, (v) => settings.setNowPlayingOptions(title: v)),
              _setting('Folder name', 'Show the current folder', Icons.folder_rounded, settings.showNowPlayingFolder, (v) => settings.setNowPlayingOptions(folder: v)),
            ]),
            const SizedBox(height: 12),
            _section('Playback controls', [
              _setting('Progress timeline', 'Show seek bar and elapsed/remaining time', Icons.linear_scale_rounded, settings.showNowPlayingTimeline, (v) => settings.setNowPlayingOptions(timeline: v)),
              _setting('Main playback controls', 'Show previous, play/pause and next', Icons.skip_next_rounded, settings.showNowPlayingTransport, (v) => settings.setNowPlayingOptions(transport: v)),
              _setting('Favorite button', 'Show the quick favorite action', Icons.star_outline_rounded, settings.showNowPlayingFavorite, (v) => settings.setNowPlayingOptions(favorite: v)),
              _setting('Track options button', 'Show download, share, queue and file actions', Icons.more_horiz_rounded, settings.showNowPlayingTrackOptions, (v) => settings.setNowPlayingOptions(trackOptions: v)),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: settings.resetNowPlayingOptions,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset to defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
