import 'package:flutter/material.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/home_server_app_bar.dart';

class NowPlayingSettingsScreen extends StatelessWidget {
  const NowPlayingSettingsScreen({super.key});

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
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
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
            ),
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
