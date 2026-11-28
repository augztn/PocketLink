import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import 'music_shortcut_customization_screen.dart';
import 'widgets/settings_components.dart';

class NowPlayingSettingsScreen extends StatefulWidget {
  const NowPlayingSettingsScreen({this.initialSearchQuery, super.key});

  final String? initialSearchQuery;

  @override
  State<NowPlayingSettingsScreen> createState() => _NowPlayingSettingsScreenState();
}

class _NowPlayingSettingsScreenState extends State<NowPlayingSettingsScreen> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialSearchQuery ?? '';
    _searchController = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Widget child) {
    if (_query.trim().isEmpty) return true;
    final tokens = _query.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((token) => token.isNotEmpty);
    if (tokens.isEmpty) return true;
    final searchable = <String>[];
    if (child is SettingsNestedGroup) searchable.add(settingsSearchableText(child));
    if (child is SettingsTile) {
      searchable.add(child.title);
      if (child.subtitle != null) searchable.add(child.subtitle!);
    }
    if (child is ListTile) {
      if (child.title is Text) searchable.add((child.title as Text).data ?? '');
      if (child.subtitle is Text) searchable.add((child.subtitle as Text).data ?? '');
    } else if (child is SwitchListTile) {
      if (child.title is Text) searchable.add((child.title as Text).data ?? '');
      if (child.subtitle is Text) searchable.add((child.subtitle as Text).data ?? '');
    } else if (child is _SwipeActionTile) {
      searchable.add(child.title);
    }
    final corpus = searchable.join(' ').toLowerCase();
    return tokens.every(corpus.contains);
  }

  List<Widget> _filtered(List<Widget> children) =>
      children.where(_matches).toList(growable: false);

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
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search in Music & Player',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            SettingsGroupCard(searchQuery: _query, children: _filtered([
              const ListTile(
                leading: Icon(Icons.touch_app_rounded),
                title: Text('Tap'),
                subtitle: Text('Open the current Now Playing screen'),
              ),
              SettingsNestedGroup(
                parent: SwitchListTile(
                  secondary: const SettingsIcon(Icons.swipe_rounded),
                  title: const Text('Swipe to change tracks'),
                  subtitle: const Text('Swipe left or right on the Music button'),
                  value: settings.musicButtonSwipeEnabled,
                  onChanged: (value) => settings.setMusicButtonOptions(
                    swipeEnabled: value,
                  ),
                ),
                expanded: settings.musicButtonSwipeEnabled || _query.isNotEmpty,
                searchQuery: _query,
                children: [
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
              ),
              SwitchListTile(
                secondary: const SettingsIcon(Icons.touch_app_outlined),
                title: const Text('Hold for shortcuts'),
                subtitle: const Text('Long-press the Music button to show quick destinations'),
                value: settings.musicButtonLongPressEnabled,
                onChanged: (value) => settings.setMusicButtonOptions(
                  longPressEnabled: value,
                ),
              ),
              SettingsTile(
                leading: const SettingsIcon(Icons.grid_view_rounded),
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
            ])),
            const SizedBox(height: 20),
            const SettingsSectionHeader('Now Playing style'),
            SettingsGroupCard(children: _filtered([
              SettingsTile(
                leading: const SettingsIcon(Icons.art_track_rounded),
                title: 'Player style',
                subtitle: switch (settings.nowPlayingPlayerStyle) {
                  'poster' => 'Poster · circular artwork and expressive track layout',
                  'lyrics' => 'Lyrics · open the existing synced-lyrics view by default',
                  _ => 'PocketLink · original player design',
                },
                trailing: DropdownButton<String>(
                  value: settings.nowPlayingPlayerStyle,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'pocketlink', child: Text('PocketLink')),
                    DropdownMenuItem(value: 'poster', child: Text('Poster')),
                    DropdownMenuItem(value: 'lyrics', child: Text('Lyrics')),
                  ],
                  onChanged: (value) {
                    if (value != null) settings.setNowPlayingPlayerStyle(value);
                  },
                ),
              ),
            ])),
            const SizedBox(height: 20),
            const SettingsSectionHeader('Mini-player and playback'),
            SettingsGroupCard(children: _filtered([
              SwitchListTile(
                secondary: const SettingsIcon(Icons.picture_in_picture_alt_rounded),
                title: const Text('Mini-player'),
                subtitle: const Text('Show the compact player above the navigation dock while music is playing'),
                value: settings.showMiniPlayer,
                onChanged: (value) => settings.setNowPlayingOptions(
                  miniPlayer: value,
                ),
              ),
              SwitchListTile(
                secondary: const SettingsIcon(Icons.swipe_rounded),
                title: const Text('Now Playing screen gestures'),
                subtitle: const Text('Swipe down to close; swipe left or right to change tracks'),
                value: settings.enableNowPlayingGestures,
                onChanged: (value) => settings.setNowPlayingOptions(
                  gestures: value,
                ),
              ),
              SwitchListTile(
                secondary: const SettingsIcon(Icons.query_stats_rounded),
                title: const Text('Show stats for nerds'),
                subtitle: const Text('Show audio codec, bitrate and sample rate in the player menu'),
                value: settings.showStatsForNerds,
                onChanged: (value) => settings.setNowPlayingOptions(
                  statsForNerds: value,
                ),
              ),
            ])),
            if (_query.isNotEmpty && _filtered([
              const ListTile(title: Text('Music dock button')),
              const SettingsTile(title: 'Player style'),
              const SettingsTile(title: 'Mini-player'),
            ]).isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No matching settings found.'),
              ),
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

class _SwipeActionTile extends SettingsTile {
  _SwipeActionTile({
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) : super(
          title: title,
          trailing: DropdownButton<String>(
            value: _NowPlayingSettingsScreenState._swipeActions.containsKey(value)
                ? value
                : 'none',
            underline: const SizedBox.shrink(),
            items: _NowPlayingSettingsScreenState._swipeActions.entries.map(
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
