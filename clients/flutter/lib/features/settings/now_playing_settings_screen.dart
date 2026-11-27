import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import 'music_shortcut_customization_screen.dart';
import 'widgets/settings_components.dart';

class NowPlayingSettingsScreen extends StatelessWidget {
  const NowPlayingSettingsScreen({super.key});

  static const _swipeActions = <String, String>{
    'next': 'Next track',
    'previous': 'Previous track',
    'none': 'No action',
  };

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Scaffold(
        appBar: PocketLinkAppBar(title: const Text('Music & Player', style: TextStyle(fontSize: 20))),
        body: ListView(
          padding: settingsListPadding(context),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                'Configure the Music button and mini-player behavior.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SettingsSectionHeader('Music dock button'),
            SettingsGroupCard(children: [
              const ListTile(
                leading: Icon(Icons.touch_app_rounded),
                title: Text('Tap'),
                subtitle: Text('Open the current Now Playing screen'),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.swipe_rounded),
                title: const Text('Swipe to change tracks'),
                subtitle: const Text('Swipe left or right on the Music button'),
                value: settings.musicButtonSwipeEnabled,
                onChanged: (value) => settings.setMusicButtonOptions(
                  swipeEnabled: value,
                ),
              ),
              if (settings.musicButtonSwipeEnabled) ...[
                _SwipeActionTile(
                  title: 'Swipe left',
                  value: settings.musicButtonSwipeLeftAction,
                  onChanged: (value) => settings.setMusicButtonOptions(
                    swipeLeftAction: value,
                  ),
                ),
                _SwipeActionTile(
                  title: 'Swipe right',
                  value: settings.musicButtonSwipeRightAction,
                  onChanged: (value) => settings.setMusicButtonOptions(
                    swipeRightAction: value,
                  ),
                ),
              ],
              SwitchListTile(
                secondary: const Icon(Icons.touch_app_outlined),
                title: const Text('Hold for shortcuts'),
                subtitle: const Text('Long-press the Music button to show quick destinations'),
                value: settings.musicButtonLongPressEnabled,
                onChanged: (value) => settings.setMusicButtonOptions(
                  longPressEnabled: value,
                ),
              ),
              SettingsTile(
                leading: const Icon(Icons.grid_view_rounded),
                title: 'Customize shortcut destinations',
                subtitle: '${settings.musicButtonShortcuts.length} destinations · reorder and choose what appears',
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: settings.musicButtonLongPressEnabled,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MusicShortcutCustomizationScreen(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const SettingsSectionHeader('Mini-player and playback'),
            SettingsGroupCard(children: [
              SwitchListTile(
                secondary: const Icon(Icons.picture_in_picture_alt_rounded),
                title: const Text('Mini-player'),
                subtitle: const Text('Show the compact player above the navigation dock while music is playing'),
                value: settings.showMiniPlayer,
                onChanged: (value) => settings.setNowPlayingOptions(
                  miniPlayer: value,
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.swipe_rounded),
                title: const Text('Now Playing screen gestures'),
                subtitle: const Text('Swipe down to close; swipe left or right to change tracks'),
                value: settings.enableNowPlayingGestures,
                onChanged: (value) => settings.setNowPlayingOptions(
                  gestures: value,
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.query_stats_rounded),
                title: const Text('Show stats for nerds'),
                subtitle: const Text('Show audio codec, bitrate and sample rate in the player menu'),
                value: settings.showStatsForNerds,
                onChanged: (value) => settings.setNowPlayingOptions(
                  statsForNerds: value,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await settings.resetMusicButtonOptions();
                  await settings.resetNowPlayingOptions();
                  await settings.resetMusicButtonShortcuts();
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset music button settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeActionTile extends StatelessWidget {
  const _SwipeActionTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SettingsTile(
    title: title,
    trailing: DropdownButton<String>(
      value: NowPlayingSettingsScreen._swipeActions.containsKey(value)
          ? value
          : 'none',
      underline: const SizedBox.shrink(),
      items: NowPlayingSettingsScreen._swipeActions.entries.map(
        (entry) => DropdownMenuItem<String>(
          value: entry.key,
          child: Text(entry.value),
        ),
      ).toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}

