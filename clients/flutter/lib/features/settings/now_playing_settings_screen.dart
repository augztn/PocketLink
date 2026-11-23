import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import 'music_shortcut_customization_screen.dart';
import 'widgets/settings_components.dart';
import '../media/now_playing_scrubber.dart';

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
            const SettingsSectionHeader('Now Playing scrubber'),
            SettingsGroupCard(children: NowPlayingScrubberStyle.values.map((style) {
              final selected = settings.nowPlayingScrubberStyle == style.key;
              return RadioListTile<String>(
                value: style.key,
                groupValue: settings.nowPlayingScrubberStyle,
                onChanged: (value) {
                  if (value != null) {
                    settings.setNowPlayingScrubberStyle(value);
                  }
                },
                title: Text(style.label),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 7, right: 12),
                  child: NowPlayingScrubberPreview(style: style),
                ),
                selected: selected,
                dense: false,
              );
            }).toList(growable: false)),
            const SizedBox(height: 20),
            const SettingsSectionHeader('Now Playing theme'),
            SettingsGroupCard(
              padding: const EdgeInsets.all(8),
              children: [
                SizedBox(
                  height: 132,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _NowPlayingThemeOption(
                        value: 'apple',
                        label: 'Apple Glass',
                        description: 'Default',
                        selected: settings.nowPlayingTheme == 'apple',
                        onTap: () => settings.setNowPlayingTheme('apple'),
                      ),
                      _NowPlayingThemeOption(
                        value: 'blur',
                        label: 'Blur',
                        description: 'Full-screen blur',
                        selected: settings.nowPlayingTheme == 'blur',
                        onTap: () => settings.setNowPlayingTheme('blur'),
                      ),
                      _NowPlayingThemeOption(
                        value: 'blurCard',
                        label: 'Blur Card',
                        description: 'Floating glass card',
                        selected: settings.nowPlayingTheme == 'blurCard',
                        onTap: () => settings.setNowPlayingTheme('blurCard'),
                      ),
                      _NowPlayingThemeOption(
                        value: 'gradient',
                        label: 'Gradient',
                        description: 'Artwork fade',
                        selected: settings.nowPlayingTheme == 'gradient',
                        onTap: () => settings.setNowPlayingTheme('gradient'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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


class _NowPlayingThemeOption extends StatelessWidget {
  const _NowPlayingThemeOption({
    required this.value,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 132,
        child: Material(
          color: selected
              ? colors.primaryContainer.withValues(alpha: 0.52)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? colors.primary : colors.outlineVariant,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _themeThumbnail(value)),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle_rounded, color: colors.primary, size: 15),
                    ],
                  ),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeThumbnail(String theme) {
    const palette = [Color(0xFF8B5CF6), Color(0xFFDB2777), Color(0xFF10111A)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: theme == 'gradient'
                    ? palette
                    : const [Color(0xFF272333), Color(0xFF101116)],
              ),
            ),
          ),
          if (theme == 'blur' || theme == 'blurCard')
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFDB2777)]),
                  ),
                ),
              ),
            ),
          if (theme == 'gradient')
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, const Color(0xFF101116).withValues(alpha: 0.9)],
                    stops: const [0.2, 1],
                  ),
                ),
              ),
            ),
          if (theme == 'apple')
            Center(
              child: Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFDB2777)]),
                ),
              ),
            ),
          if (theme == 'blurCard')
            Center(
              child: Container(
                width: 82,
                height: 37,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ),
          if (theme == 'blur')
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 25),
            ),
        ],
      ),
    );
  }
}
