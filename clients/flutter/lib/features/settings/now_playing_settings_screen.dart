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
                  secondary: const Icon(Icons.swipe_rounded),
                  title: const Text('Swipe gestures'),
                  subtitle: const Text('Swipe down to close; swipe left or right to change tracks'),
                  value: settings.enableNowPlayingGestures,
                  onChanged: (value) => settings.setNowPlayingOptions(gestures: value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.folder_rounded),
                  title: const Text('Folder name'),
                  subtitle: const Text('Show the current folder below the track title'),
                  value: settings.showNowPlayingFolder,
                  onChanged: (value) => settings.setNowPlayingOptions(folder: value),
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
