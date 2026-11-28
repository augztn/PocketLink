import 'dart:io';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/server_api.dart';
import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_backup_service.dart';
import 'widgets/settings_components.dart';
import 'navigation_customization_screen.dart';
import 'now_playing_settings_screen.dart';
import 'video_player_settings_screen.dart';
import '../about/about_screen.dart';
import '../downloads/download_manager_service.dart';
import '../media/discover/imported_playlist_manager_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.api, this.onOpenSavedServers, this.category, this.initialSearchQuery, super.key});

  final ServerApi? api;

  final VoidCallback? onOpenSavedServers;
  final String? category;
  final String? initialSearchQuery;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettings.instance;
  bool _clearingCache = false;
  bool _exportingLogs = false;
  bool _exportingSettings = false;
  bool _importingSettings = false;
  double? _pendingAnimationSpeed;
  double? _pendingBlurStrength;
  double? _pendingGlassBlurStrength;
  double? _pendingLyricsInactiveBlur;
  double? _pendingThumbnailCornerRadius;
  double? _pendingLyricsTextSize;
  double? _pendingLyricsLineSpacing;
  String _settingsSearchQuery = '';
  final TextEditingController _settingsSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialSearchQuery;
    if (initialQuery != null && initialQuery.trim().isNotEmpty) {
      _settingsSearchQuery = initialQuery;
      _settingsSearchController.text = initialQuery;
    }
  }

  Iterable<String> _searchableText(Widget widget) sync* {
    if (widget is Text) {
      final value = widget.data;
      if (value != null) yield value;
      return;
    }
    if (widget is ListTile) {
      if (widget.title != null) yield* _searchableText(widget.title!);
      if (widget.subtitle != null) yield* _searchableText(widget.subtitle!);
      if (widget.leading != null) yield* _searchableText(widget.leading!);
      if (widget.trailing != null) yield* _searchableText(widget.trailing!);
      return;
    }
    if (widget is SwitchListTile) {
      yield* _searchableText(widget.title);
      if (widget.subtitle != null) yield* _searchableText(widget.subtitle!);
      if (widget.secondary != null) yield* _searchableText(widget.secondary!);
      return;
    }
    if (widget is Padding) {
      yield* _searchableText(widget.child);
      return;
    }
    if (widget is Column) {
      for (final child in widget.children) {
        yield* _searchableText(child);
      }
      return;
    }
    if (widget is Row) {
      for (final child in widget.children) {
        yield* _searchableText(child);
      }
      return;
    }
    if (widget is Container && widget.child != null) {
      yield* _searchableText(widget.child!);
      return;
    }
    if (widget is SizedBox && widget.child != null) {
      yield* _searchableText(widget.child!);
      return;
    }
    if (widget is Align) {
      if (widget.child != null) yield* _searchableText(widget.child!);
      return;
    }
    if (widget is SettingsGroupCard) {
      for (final child in widget.children) {
        yield* _searchableText(child);
      }
    }
  }

  bool _matchesCategorySearch(Widget child, {String sectionTitle = ''}) {
    final tokens = _settingsSearchQuery
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty);
    if (tokens.isEmpty) return true;
    final corpus = '${sectionTitle.toLowerCase()} ${_searchableText(child).join(' ').toLowerCase()}';
    return tokens.every(corpus.contains);
  }

  Future<void> _openDiscoverPlaylists() async {
    final api = widget.api;
    if (api == null) {
      _message('Connect to your PocketLink server to manage Discover playlists.');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      settings: const RouteSettings(
        name: PocketLinkRouteNames.discoverPlaylists,
      ),
      builder: (_) => ImportedPlaylistManagerScreen(api: api),
    ));
  }

  Future<void> _importCustomFont() async {
    try {
      final picked = await file_picker.FilePicker.pickFile(
        type: file_picker.FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );
      if (!mounted || picked == null) return;
      final extension = picked.extension?.toLowerCase();
      if (extension != 'ttf' && extension != 'otf') {
        _message('Select a .ttf or .otf font file.');
        return;
      }
      final fileLength = picked.lengthSync() ?? await picked.length();
      if (fileLength != null && fileLength > 20 * 1024 * 1024) {
        _message('Font files must be 20 MB or smaller.');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        _message('Font files must be 20 MB or smaller.');
        return;
      }
      final directory = Directory('${(await getApplicationSupportDirectory()).path}/fonts');
      await directory.create(recursive: true);
      final family = 'PocketLinkCustom_${DateTime.now().microsecondsSinceEpoch}';
      final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
      final destination = File('${directory.path}/$family.$extension');
      await destination.writeAsBytes(bytes, flush: true);
      try {
        await _settings.setCustomFont(path: destination.path, family: family, name: safeName);
      } catch (_) {
        if (await destination.exists()) await destination.delete();
        rethrow;
      }
      if (mounted) _message('Custom font applied throughout PocketLink.');
    } catch (_) {
      if (mounted) _message('Could not load this font. Choose a valid TTF or OTF file.');
    }
  }

  Future<void> _resetCustomFont() async {
    try {
      await _settings.clearCustomFont();
      if (mounted) _message('PocketLink default font restored.');
    } catch (_) {
      if (mounted) _message('Could not restore the default font.');
    }
  }

  Future<void> _chooseDownloadDirectory() async {
    try {
      final path = await file_picker.FilePicker.getDirectoryPath();
      if (path != null) await _settings.setDownloadDirectory(path);
    } catch (_) {
      _message('Could not select a download directory.');
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cached data?'),
        content: const Text('This clears temporary app files and Flutter image cache. Your downloads, favourites and server files are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear cache')),
        ],
      ),
    );
    if (confirmed != true || _clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      final directory = await getTemporaryDirectory();
      if (await directory.exists()) {
        await for (final entity in directory.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } on FileSystemException {
            // A transient or locked cache item should not block the remaining cleanup.
          }
        }
      }
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      if (mounted) _message('Temporary files and image cache cleared.');
    } catch (_) {
      if (mounted) _message('Could not clear all cached data.');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _exportLogs() async {
    if (_exportingLogs) return;
    setState(() => _exportingLogs = true);
    try {
      final file = await AppLogger.createDiagnosticFile();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'PocketLink diagnostic logs',
          text: 'Review the diagnostic file before sharing. It may contain server addresses and filesystem error details.',
        ),
      );
      await AppLogger.info('Diagnostic log export requested from Settings');
    } catch (error, stack) {
      await AppLogger.error('Settings diagnostic export failed', error: error, stackTrace: stack);
      if (mounted) _message('Could not export diagnostic logs.');
    } finally {
      if (mounted) setState(() => _exportingLogs = false);
    }
  }

  Future<void> _exportSettingsBackup() async {
    if (_exportingSettings || _importingSettings) return;
    setState(() => _exportingSettings = true);
    try {
      final bytes = await SettingsBackupService.exportBackup();
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/pocketlink-settings-backup.json');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'PocketLink settings backup',
        text: 'Settings only. Server profiles, credentials and device-specific storage access are not included.',
      ));
      if (mounted) _message('Settings backup is ready to save or share.');
    } catch (error, stack) {
      await AppLogger.error('Settings backup export failed', error: error, stackTrace: stack);
      if (mounted) _message('Could not export settings backup.');
    } finally {
      if (mounted) setState(() => _exportingSettings = false);
    }
  }

  Future<void> _importSettingsBackup() async {
    if (_exportingSettings || _importingSettings) return;
    try {
      final pickedFile = await file_picker.FilePicker.pickFile(
        type: file_picker.FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted || pickedFile == null) return;
      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore settings?'),
          content: const Text(
            'This replaces supported PocketLink preferences on this device. '
            'Server profiles, credentials, downloads, files and storage permissions are not changed.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _importingSettings = true);
      final count = await SettingsBackupService.importBackup(bytes);
      await _settings.reloadPreferences();
      if (mounted) {
        setState(() {});
        _message('Restored $count settings successfully.');
      }
    } catch (error, stack) {
      await AppLogger.error('Settings backup import failed', error: error, stackTrace: stack);
      if (mounted) _message('Backup was not restored. The file may be invalid or unsupported.');
    } finally {
      if (mounted) setState(() => _importingSettings = false);
    }
  }

  Future<void> _customizeDashboardOrder() async {
    const labels = <String, ({String title, String description, IconData icon})>{
      'search': (title: 'Global search', description: 'Search files and folders from Home', icon: Icons.search_rounded),
      'quick': (title: 'Quick actions', description: 'Upload, Drives, Favorites and shortcuts', icon: Icons.dashboard_customize_rounded),
      'transfers': (title: 'Active transfers', description: 'Live upload and download progress', icon: Icons.swap_vert_rounded),
      'continue': (title: 'Continue browsing', description: 'Recently opened folders, files and tracks', icon: Icons.history_rounded),
      'recent': (title: 'Recent files', description: 'Recently changed files from the server', icon: Icons.insert_drive_file_outlined),
      'storage': (title: 'Storage & host health', description: 'Mounted volumes, device health and media scan status', icon: Icons.storage_rounded),
    };
    var draft = List<String>.of(_settings.homeSectionOrder);
    final visible = <String>{
      if (_settings.showGlobalSearch) 'search',
      if (_settings.showQuickActions) 'quick',
      if (_settings.showActiveTransfers) 'transfers',
      if (_settings.showLibrary) 'continue',
      if (_settings.showRecentFiles) 'recent',
      if (_settings.showStorageOverview) 'storage',
    };
    final result = await showDialog<({List<String> order, Set<String> visible})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customize Home'),
          content: SizedBox(
            width: 440,
            height: 470,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose which sections appear and drag to set their order. Server status stays at the top.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: draft.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setDialogState(() {
                        final item = draft.removeAt(oldIndex);
                        draft.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final id = draft[index];
                      final detail = labels[id]!;
                      final enabled = visible.contains(id);
                      return ListTile(
                        key: ValueKey(id),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(detail.icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        title: Text(detail.title),
                        subtitle: Text(detail.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: enabled,
                              onChanged: (value) => setDialogState(() {
                                if (value) {
                                  visible.add(id);
                                } else {
                                  visible.remove(id);
                                }
                              }),
                            ),
                            const Icon(Icons.drag_handle_rounded),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => setDialogState(() {
                draft = List.of(AppSettings.homeSectionDefaults);
                visible
                  ..clear()
                  ..addAll(AppSettings.homeSectionDefaults);
              }),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                (order: List<String>.of(draft), visible: Set<String>.of(visible)),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _settings.setHomeSectionOrder(result.order);
    await _settings.setHomeSections(
      globalSearch: result.visible.contains('search'),
      quickActions: result.visible.contains('quick'),
      activeTransfers: result.visible.contains('transfers'),
      library: result.visible.contains('continue'),
      recentFiles: result.visible.contains('recent'),
      storageOverview: result.visible.contains('storage'),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _section(String title, List<Widget> children) {
    final visibleChildren = children.where((child) => _matchesCategorySearch(child, sectionTitle: title)).toList(growable: false);
    if (visibleChildren.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionHeader(title),
          SettingsGroupCard(children: visibleChildren),
        ],
      ),
    );
  }

  String _pageTitle(String? category) => switch (category) {
        'Appearance' => 'Appearance',
        'Customisation' => 'Customisation',
        'Navigation' => 'Navigation',
        'Music' => 'Music & Playback',
        'Dashboard & Shortcuts' => 'Dashboard',
        'Network' => 'Network',
        'Diagnostics' => 'Diagnostics',
        'Music / Now Playing Button' => 'Music & Player',
        'Customize Navigation Bar' => 'Navigation',
        _ => category ?? 'Settings',
      };

  PageRoute<void> _categoryRoute(String id, WidgetBuilder builder) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: PocketLinkRouteNames.settingsCategory(id),
        ),
        builder: builder,
      );

  void _openCategory(String id, {String? searchQuery}) {
    final route = switch (id) {
      'navigation-customize' => _categoryRoute(
          id,
          (_) => const NavigationCustomizationScreen(),
        ),
      'audio' || 'now-playing' => _categoryRoute(
          id,
          (_) => NowPlayingSettingsScreen(initialSearchQuery: searchQuery),
        ),
      'video' => _categoryRoute(
          id,
          (_) => const VideoPlayerSettingsScreen(),
        ),
      'about' => _categoryRoute(id, (_) => const AboutScreen()),
      _ => _categoryRoute(
          id,
          (_) => SettingsScreen(
            api: widget.api,
            onOpenSavedServers: widget.onOpenSavedServers,
            initialSearchQuery: searchQuery,
            category: switch (id) {
              'appearance' => 'Appearance',
              'customization' => 'Customisation',
              'navigation' => 'Navigation',
              'dashboard' => 'Dashboard & Shortcuts',
              'music' => 'Music',
              'discover' => 'Discover',
              'storage' => 'Storage',
              'network' || 'connectivity' => 'Network',
              'diagnostics' || 'maintenance' => 'Diagnostics',
              _ => 'Network',
            },
          ),
        ),
    };
    Navigator.of(context).push(route);
  }

  List<String> _matchingSettingLabels(String id) {
    final tokens = _settingsSearchQuery
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    const entries = <String, Map<String, String>>{
      'appearance': {
        'Accent colour': 'accent color theme palette blue purple pink red orange green teal cyan',
        'Theme mode': 'theme light dark system brightness',
        'AMOLED mode': 'amoled oled black deep black',
        'Liquid Glass UI': 'liquid glass frosted reflections surfaces',
        'Progressive Blur': 'progressive blur shader fade header',
        'Live preview': 'preview sample appearance',
        'Reset appearance': 'reset defaults restore theme',
      },
      'customization': {
        'App animations': 'animations motion transition reduce motion disable global system wide',
        'Animation speed': 'animations motion faster slower speed duration 0.5 2x',
        'Page transitions': 'screen route navigation transition slide animation',
        'Lyrics animations': 'lyrics motion animation emphasis pulse',
        'Glass blur strength': 'liquid glass frosted blur strength sigma',
        'Lyrics glow': 'lyrics glow light accent effect',
        'Lyrics bloom': 'lyrics bloom soft light blur effect',
        'Lyrics soft light': 'lyrics soft light text glow',
        'Lyrics inactive blur': 'lyrics inactive line blur focus',
        'Lyrics text size': 'lyrics font size text scale typography 14 44',
        'Lyrics line spacing': 'lyrics line height spacing vertical gap',
        'Lyrics motion style': 'lyrics animation motion legacy boring plain transition',
        'Custom font': 'font typography typeface ttf otf import install default reset',
        'Theme mode': 'theme light dark system brightness',
        'AMOLED mode': 'amoled oled black deep black',
        'Liquid Glass UI': 'liquid glass frosted reflections surfaces',
        'Progressive Blur': 'progressive blur shader fade header',
        'Blur': 'blur glass frosted strength',
      },
      'navigation': {
        'Navigation bar and dock': 'navigation dock tabs destinations visible hidden reorder',
        'Music button': 'browse music player shortcut button',
        'Dashboard sections': 'dashboard home quick actions continue browsing recent files global search transfers storage overview',
        'Floating FAB': 'floating action button fab shortcuts appearance',
      },
      'storage': {
        'Download location': 'download directory folder location',
        'Concurrent downloads': 'concurrency simultaneous downloads',
        'Wi-Fi only': 'wifi mobile data network',
        'Auto-resume': 'resume unfinished downloads launch',
        'Clear cache': 'temporary files image cache clear',
      },
      'now-playing': {
        'Player style': 'now playing player layout poster pocketlink lyrics artwork',
        'Mini-player': 'mini player compact pill artwork playback controls',
        'Playback gestures': 'swipe dismiss change tracks seek',
      },
      'music': {
        'Music button and mini-player': 'audio now playing gestures shortcuts mini player',
        'Playback gestures': 'swipe dismiss change tracks seek',
        'Scrubber and player theme': 'progress bar waveform appearance glass blur gradient',
        'Discover': 'music discovery explore recommendations',
        'Lossless matching': 'flac alac wav matching',
        'Lyrics and artwork': 'synced plain lyrics thumbnails images artwork',
        'Video player': 'video playback controls scaling subtitles',
        'Playlist import and export': 'import export playlists spotify csv m3u',
        'Audio quality and resolver': 'best available balanced data saver bitrate newpipe player api stream resolver',
        'Content region': 'region catalogue country',
      },
      'network': {
        'Saved servers': 'server connections switch host profiles network connectivity',
      },
      'diagnostics': {
        'Export settings': 'backup export json preferences',
        'Import settings': 'restore import json preferences',
        'Diagnostic logs': 'diagnostics troubleshooting logs export share',
      },
      'about': {
        'Version information': 'version about pocketlink',
        'Licenses': 'licenses acknowledgements architecture',
      },
    };
    final options = entries[id];
    if (options == null) return const [];
    if (tokens.isEmpty) return options.keys.toList(growable: false);
    const categoryTerms = <String, String>{
      'appearance': 'appearance visual effects',
      'customization': 'customization customisation appearance theme animations motion visual effects blur',
      'navigation': 'navigation bar dock dashboard home fab',
      'storage': 'storage downloads files transfers download location',
      'music': 'music audio playback discover video lyrics playlists',
      'now-playing': 'now playing player mini-player poster lyrics playback',
      'network': 'network connectivity connection server',
      'diagnostics': 'diagnostics maintenance backup restore logs troubleshooting',
      'about': 'about pocketlink',
    };
    return options.entries
        .where((entry) {
          final corpus = '${id} ${categoryTerms[id] ?? ''} ${entry.key.toLowerCase()} ${entry.value} wi fi';
          return tokens.every(corpus.contains);
        })
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  bool _categoryMatches(String id) => _matchingSettingLabels(id).isNotEmpty;

  List<Widget> _globalSearchResultTiles() {
    if (_settingsSearchQuery.trim().isEmpty) return const [];
    const categories = <String, String>{
      'appearance': 'Appearance',
      'customization': 'Customisation',
      'navigation': 'Navigation',
      'storage': 'Storage',
      'now-playing': 'Now Playing',
      'music': 'Music',
      'network': 'Network',
      'diagnostics': 'Diagnostics',
      'about': 'About',
    };
    final results = <Widget>[];
    for (final entry in categories.entries) {
      for (final label in _matchingSettingLabels(entry.key)) {
        results.add(
          ListTile(
            key: ValueKey('settings-search-${entry.key}-$label'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: const Icon(Icons.tune_rounded, size: 20),
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(entry.value),
            trailing: const Icon(Icons.north_east_rounded, size: 18),
            onTap: () => _openCategory(entry.key, searchQuery: _settingsSearchQuery),
          ),
        );
      }
    }
    if (results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'No matching settings found.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SettingsSectionHeader('Matching settings'),
      ),
      SettingsGroupCard(children: results),
      const SizedBox(height: 18),
    ];
  }

  Future<void> _resetAppearance() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset appearance settings?'),
        content: const Text(
          'Restore System theme and accent colour, reset glass and header blur, artwork rounding, lyrics effects and PocketLink animations. Disable Liquid Glass and restore Progressive Blur. Other settings will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset appearance'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _settings.setThemeMode(ThemeMode.system);
    await _settings.setAccentColor(AppSettings.accentColorValues.first);
    await _settings.setBlurStrength(24.0);
    await _settings.setGlassBlurStrength(20.0);
    await _settings.setThumbnailCornerRadius(10.0);
    await _settings.setUseLiquidGlass(false);
    await _settings.setProgressiveBlurEnabled(true);
    await _settings.setAnimationsEnabled(true);
    await _settings.setAnimationSpeed(1.0);
    await _settings.setPageTransitionsEnabled(true);
    await _settings.setLyricsAnimationsEnabled(true);
    await _settings.setLyricsOptions(
      textSize: 31.0,
      lineSpacing: 1.22,
      motionStyle: 'motion',
      glow: false,
      bloom: false,
      softLight: false,
      inactiveBlur: 1.7,
    );
    if (mounted) _message('Appearance settings restored to defaults.');
  }

  Widget _categoryIntro(String category) {
    final descriptions = <String, String>{
      'Appearance': 'Theme, AMOLED black mode, blur, colors and visual effects.',
      'Customisation': 'Control PocketLink-wide motion, animation speed, theme and visual effects.',
      'Navigation': 'Dock, destinations, dashboard sections and floating shortcuts.',
      'Music': 'Music library, playback, Discover, lyrics and video preferences.',
      'Storage': 'Download location, download behavior and temporary cache.',
      'Network': 'Manage saved PocketLink servers and connection switching.',
      'Diagnostics': 'Back up settings, restore preferences and export diagnostic logs.',
      'Dashboard & Shortcuts': 'Choose which Home sections appear and arrange their order.',
      'Discover': 'Configure music discovery, matching, playback preferences and playlists.',
    };
    final description = descriptions[category];
    if (description == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        description,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<Widget> _homeSettingsChildren() => [
    if (_categoryMatches('customization') || _categoryMatches('appearance'))
      _categoryTile(
        id: 'customization',
        icon: Icons.palette_rounded,
        tint: const Color(0xFF8D72E8),
        title: 'Customisation',
      ),
    if (_categoryMatches('navigation'))
      _categoryTile(
        id: 'navigation',
        icon: Icons.tune_rounded,
        tint: const Color(0xFF60A5FA),
        title: 'Navigation',
      ),
    if (_categoryMatches('storage'))
      _categoryTile(
        id: 'storage',
        icon: Icons.storage_rounded,
        tint: const Color(0xFFFBBF24),
        title: 'Storage',
      ),
    if (_categoryMatches('now-playing'))
      _categoryTile(
        id: 'now-playing',
        icon: Icons.album_rounded,
        tint: const Color(0xFFDB79A8),
        title: 'Now Playing',
      ),
    if (_categoryMatches('music'))
      _categoryTile(
        id: 'music',
        icon: Icons.graphic_eq_rounded,
        tint: const Color(0xFFDB79A8),
        title: 'Music',
      ),
    if (_categoryMatches('network'))
      _categoryTile(
        id: 'network',
        icon: Icons.wifi_rounded,
        tint: const Color(0xFF4ADE80),
        title: 'Network',
      ),
    if (_categoryMatches('diagnostics'))
      _categoryTile(
        id: 'diagnostics',
        icon: Icons.build_circle_outlined,
        tint: const Color(0xFF60A5FA),
        title: 'Diagnostics',
      ),
    if (_categoryMatches('about'))
      _categoryTile(
        id: 'about',
        icon: Icons.info_outline_rounded,
        tint: const Color(0xFFFBBF24),
        title: 'About',
      ),
    if (!_categoryMatches('appearance') &&
        !_categoryMatches('customization') &&
        !_categoryMatches('navigation') &&
        !_categoryMatches('storage') &&
        !_categoryMatches('music') &&
        !_categoryMatches('now-playing') &&
        !_categoryMatches('network') &&
        !_categoryMatches('diagnostics') &&
        !_categoryMatches('about'))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            'No settings found for “$_settingsSearchQuery”.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
  ];

  Widget _categoryTile({
    required String id,
    required IconData icon,
    required Color tint,
    required String title,
  }) {
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$id:$_settingsSearchQuery'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final progress = MediaQuery.of(context).disableAnimations ? 1.0 : value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - progress)),
            child: Transform.scale(
              scale: 0.975 + 0.025 * progress,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openCategory(id),
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: tint, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _settingsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: widget.category == null
            ? null
            : PocketLinkAppBar(
          title: Text(_pageTitle(widget.category), style: const TextStyle(fontSize: 20)),
          actions: [
            PocketLinkAppBarAction(
              label: 'Return to Home',
              icon: Icons.home_rounded,
              onPressed: () => PocketLinkAppBar.goToDashboard(context),
            ),
          ],
          showHome: false,
          showMoreMenu: true,
          feathered: true,
        ),
        body: Builder(
          builder: (bodyContext) {
            final layoutInsets = LayoutInsetsScope.of(bodyContext);
            final bottomClearance = settingsListBottomPadding(
              bodyContext,
              miniPlayerVisible: layoutInsets.hasActiveMiniPlayer,
            );
            final topClearance = layoutInsets.topClearance;
            return Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    if (widget.category == null)
                      SliverAppBar(
                        pinned: true,
                        floating: false,
                        automaticallyImplyLeading: false,
                        expandedHeight: 148,
                        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        flexibleSpace: LayoutBuilder(
                          builder: (context, constraints) {
                            final progress = ((constraints.maxHeight - kToolbarHeight) /
                                    (148 - kToolbarHeight))
                                .clamp(0.0, 1.0);
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Opacity(
                                    opacity: progress,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.tune_rounded, color: Theme.of(context).colorScheme.onSurface),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Settings',
                                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                              fontSize: 34,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.7,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Opacity(
                                    opacity: 1 - progress,
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 20),
                                      child: Text(
                                        'Settings',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(64),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: TextField(
                              controller: _settingsSearchController,
                              onChanged: (value) => setState(() => _settingsSearchQuery = value),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Search settings',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _settingsSearchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: () {
                                          _settingsSearchController.clear();
                                          setState(() => _settingsSearchQuery = '');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        widget.category == null ? 12 : topClearance,
                        16,
                        bottomClearance,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          widget.category == null
                              ? [
                                  ..._globalSearchResultTiles(),
                                  ..._homeSettingsChildren().skip(2),
                                ]
                              : [
                if (widget.category != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: _settingsSearchController,
                      onChanged: (value) => setState(() => _settingsSearchQuery = value),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search in ${_pageTitle(widget.category)}',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _settingsSearchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _settingsSearchController.clear();
                                  setState(() => _settingsSearchQuery = '');
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
                  ),
                if (widget.category != null) _categoryIntro(widget.category!),
                if (widget.category == 'Navigation')
                  _section('Navigation & Home', [
                    ListTile(
                      leading: const Icon(Icons.dock_rounded),
                      title: const Text('Customize Navigation Bar'),
                      subtitle: const Text('Choose, show, hide and reorder destinations'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory('navigation-customize'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.dashboard_customize_rounded),
                      title: const Text('Dashboard & Shortcuts'),
                      subtitle: const Text('Home sections, quick actions and floating shortcuts'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory('dashboard'),
                    ),
                  ]),
                if (widget.category == 'Music')
                  _section('Music & Playback', [
                    ListTile(
                      leading: const Icon(Icons.graphic_eq_rounded),
                      title: const Text('Audio & Now Playing'),
                      subtitle: const Text('Music button gestures, shortcuts and mini-player'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory('audio'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.explore_rounded),
                      title: const Text('Discover'),
                      subtitle: const Text('Discovery feed, matching, lyrics and playlists'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory('discover'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.movie_creation_rounded),
                      title: const Text('Video Player'),
                      subtitle: const Text('Playback gestures, controls, scaling and subtitles'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openCategory('video'),
                    ),
                  ]),
                if (widget.category == 'Diagnostics')
                  _section('Settings Backup', [
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text('Export settings'),
                      subtitle: const Text('Create a portable JSON backup of supported preferences'),
                      trailing: _exportingSettings
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.ios_share_rounded),
                      onTap: _exportingSettings || _importingSettings ? null : _exportSettingsBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: const Text('Import settings'),
                      subtitle: const Text('Restore preferences from a PocketLink backup'),
                      trailing: _importingSettings
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.folder_open_rounded),
                      onTap: _exportingSettings || _importingSettings ? null : _importSettingsBackup,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(
                        'Backups include supported app preferences only. Theme and download location stay unchanged; server profiles, credentials, storage permissions, downloads and personal files are excluded.',
                      ),
                    ),
                  ]),
                if (widget.category == 'Appearance' || widget.category == 'Customisation')
                  _section('Motion', [
                    SwitchListTile(
                      secondary: const Icon(Icons.animation_rounded),
                      title: const Text('Animations'),
                      subtitle: const Text('Apply motion preferences across PocketLink screens and controls'),
                      value: _settings.animationsEnabled,
                      onChanged: _settings.setAnimationsEnabled,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.screen_share_outlined),
                      title: const Text('Page transitions'),
                      subtitle: const Text('Enable the shared slide and scale transition between screens'),
                      value: _settings.pageTransitionsEnabled,
                      onChanged: _settings.animationsEnabled ? _settings.setPageTransitionsEnabled : null,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.lyrics_rounded),
                      title: const Text('Lyrics animations'),
                      subtitle: const Text('Control active-line emphasis and instrumental pulse separately'),
                      value: _settings.lyricsAnimationsEnabled,
                      onChanged: _settings.animationsEnabled ? _settings.setLyricsAnimationsEnabled : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('Animation speed')),
                              Text('${(_pendingAnimationSpeed ?? _settings.animationSpeed).toStringAsFixed(1)}×'),
                            ],
                          ),
                          Slider(
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            value: (_pendingAnimationSpeed ?? _settings.animationSpeed).clamp(0.5, 2.0).toDouble(),
                            onChanged: _settings.animationsEnabled
                                ? (value) => setState(() => _pendingAnimationSpeed = value)
                                : null,
                            onChangeEnd: _settings.animationsEnabled
                                ? (value) async {
                                    setState(() => _pendingAnimationSpeed = null);
                                    await _settings.setAnimationSpeed(value);
                                  }
                                : null,
                          ),
                          Text(
                            '0.5× is slower · 1× is normal · 2× is faster. This scales Flutter animations throughout PocketLink.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                if (widget.category == 'Customisation')
                  _section('Typography', [
                    ListTile(
                      leading: const Icon(Icons.font_download_rounded),
                      title: const Text('Custom font'),
                      subtitle: Text(_settings.customFontName ?? 'PocketLink default font'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _importCustomFont,
                    ),
                    if (_settings.customFontFamily != null)
                      ListTile(
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: const Text('Restore default font'),
                        subtitle: const Text('Remove the imported font and use PocketLink typography'),
                        onTap: _resetCustomFont,
                      ),
                  ]),
                if (widget.category == 'Customisation')
                  _section('Lyrics', [
                    ListTile(
                      leading: const Icon(Icons.lyrics_rounded),
                      title: const Text('Lyrics motion style'),
                      subtitle: Text(switch (_settings.lyricsMotionStyle) {
                        'motion' => 'Motion · Fade and scale emphasis',
                        'legacy' => 'Legacy · Fade emphasis',
                        'boring' => 'Boring · Instant emphasis',
                        _ => 'Plain · Minimal emphasis',
                      }),
                      trailing: DropdownButton<String>(
                        value: _settings.lyricsMotionStyle,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'motion', child: Text('Motion')),
                          DropdownMenuItem(value: 'legacy', child: Text('Legacy')),
                          DropdownMenuItem(value: 'boring', child: Text('Boring')),
                          DropdownMenuItem(value: 'plain', child: Text('Plain')),
                        ],
                        onChanged: (value) {
                          if (value != null) _settings.setLyricsOptions(motionStyle: value);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Expanded(child: Text('Lyrics text size')),
                            Text('${(_pendingLyricsTextSize ?? _settings.lyricsTextSize).round()} sp'),
                          ]),
                          Slider(
                            min: 14,
                            max: 44,
                            divisions: 30,
                            value: (_pendingLyricsTextSize ?? _settings.lyricsTextSize).clamp(14.0, 44.0).toDouble(),
                            onChanged: (value) => setState(() => _pendingLyricsTextSize = value),
                            onChangeEnd: (value) async {
                              setState(() => _pendingLyricsTextSize = null);
                              await _settings.setLyricsOptions(textSize: value);
                            },
                          ),
                          Row(children: [
                            const Expanded(child: Text('Lyrics line spacing')),
                            Text('${(_pendingLyricsLineSpacing ?? _settings.lyricsLineSpacing).toStringAsFixed(2)}×'),
                          ]),
                          Slider(
                            min: 0.8,
                            max: 2.0,
                            divisions: 12,
                            value: (_pendingLyricsLineSpacing ?? _settings.lyricsLineSpacing).clamp(0.8, 2.0).toDouble(),
                            onChanged: (value) => setState(() => _pendingLyricsLineSpacing = value),
                            onChangeEnd: (value) async {
                              setState(() => _pendingLyricsLineSpacing = null);
                              await _settings.setLyricsOptions(lineSpacing: value);
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Lyrics glow'),
                            subtitle: const Text('Accent-colour halo on the active line'),
                            value: _settings.lyricsGlow,
                            onChanged: (value) => _settings.setLyricsOptions(glow: value),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Lyrics bloom'),
                            subtitle: const Text('Soft white bloom around the active line'),
                            value: _settings.lyricsBloom,
                            onChanged: (value) => _settings.setLyricsOptions(bloom: value),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Lyrics soft light'),
                            subtitle: const Text('Softer active-line white and subtle halo'),
                            value: _settings.lyricsSoftLight,
                            onChanged: (value) => _settings.setLyricsOptions(softLight: value),
                          ),
                          Row(children: [
                            const Expanded(child: Text('Inactive line blur')),
                            Text('${(_pendingLyricsInactiveBlur ?? _settings.lyricsInactiveBlur).toStringAsFixed(1)}'),
                          ]),
                          Slider(
                            min: 0,
                            max: 4,
                            divisions: 16,
                            value: (_pendingLyricsInactiveBlur ?? _settings.lyricsInactiveBlur).clamp(0.0, 4.0).toDouble(),
                            onChanged: (value) => setState(() => _pendingLyricsInactiveBlur = value),
                            onChangeEnd: (value) async {
                              setState(() => _pendingLyricsInactiveBlur = null);
                              await _settings.setLyricsOptions(inactiveBlur: value);
                            },
                          ),
                          Text(
                            'These controls affect the existing Now Playing lyrics view only.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                if (widget.category == 'Appearance' || widget.category == 'Customisation')
                  _section('Appearance & Theme', [
                    ListTile(
                      leading: const Icon(Icons.palette_rounded),
                      title: const Text('Theme mode'),
                      subtitle: Text(
                        _settings.amoled
                            ? 'AMOLED black'
                            : switch (_settings.themeMode) {
                                ThemeMode.light => 'Light',
                                ThemeMode.dark => 'Dark',
                                ThemeMode.system => 'System default',
                              },
                      ),
                      trailing: DropdownButton<String>(
                        value: _settings.amoled ? 'amoled' : _settings.themeMode.name,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'system', child: Text('System')),
                          DropdownMenuItem(value: 'light', child: Text('Light')),
                          DropdownMenuItem(value: 'dark', child: Text('Dark')),
                          DropdownMenuItem(value: 'amoled', child: Text('AMOLED')),
                        ],
                        onChanged: (value) {
                          if (value == 'amoled') {
                            _settings.setAmoled(true);
                          } else if (value != null) {
                            _settings.setThemeMode(ThemeMode.values.byName(value));
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.blur_on_rounded),
                      title: const Text('Liquid Glass UI'),
                      subtitle: const Text(
                        'Frosted blur, glass reflections and refined floating surfaces',
                      ),
                      value: _settings.useLiquidGlass,
                      onChanged: _settings.setUseLiquidGlass,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.blur_circular_rounded),
                      title: const Text('Progressive Blur'),
                      subtitle: const Text(
                        'Enable the continuous blur fade behind shared screen headers',
                      ),
                      value: _settings.progressiveBlurEnabled,
                      onChanged: _settings.setProgressiveBlurEnabled,
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('Blur strength')),
                              Text('${(_pendingBlurStrength ?? _settings.blurStrength).round()}'),
                            ],
                          ),
                          Slider(
                            min: 0,
                            max: 32,
                            divisions: 32,
                            value: (_pendingBlurStrength ?? _settings.blurStrength).clamp(0.0, 32.0).toDouble(),
                            onChanged: _settings.progressiveBlurEnabled
                                ? (value) => setState(() => _pendingBlurStrength = value)
                                : null,
                            onChangeEnd: _settings.progressiveBlurEnabled
                                ? (value) async {
                                    setState(() => _pendingBlurStrength = null);
                                    await _settings.setBlurStrength(value);
                                  }
                                : null,
                          ),
                          Text(
                            'Adjusts the shared header blur. Set to 0 for no blur.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Expanded(child: Text('Glass surface blur')),
                            Text('${(_pendingGlassBlurStrength ?? _settings.glassBlurStrength).round()}'),
                          ]),
                          Slider(
                            min: 0,
                            max: 32,
                            divisions: 32,
                            value: (_pendingGlassBlurStrength ?? _settings.glassBlurStrength).clamp(0.0, 32.0).toDouble(),
                            onChanged: _settings.useLiquidGlass
                                ? (value) => setState(() => _pendingGlassBlurStrength = value)
                                : null,
                            onChangeEnd: _settings.useLiquidGlass
                                ? (value) async {
                                    setState(() => _pendingGlassBlurStrength = null);
                                    await _settings.setGlassBlurStrength(value);
                                  }
                                : null,
                          ),
                          Text(
                            'Controls blur on Liquid Glass surfaces. Enable Liquid Glass to adjust it; 0 removes the blur while keeping the surface.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live appearance preview',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _settings.amoled
                                  ? Colors.black
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.palette_rounded,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('PocketLink', style: TextStyle(fontWeight: FontWeight.w700)),
                                      Text(
                                        '${_settings.amoled ? 'AMOLED black' : _settings.themeMode.name[0].toUpperCase() + _settings.themeMode.name.substring(1)} · Glass ${_settings.useLiquidGlass ? 'On' : 'Off'} · Blur ${_settings.progressiveBlurEnabled ? 'On' : 'Off'}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Accent colour',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final value in AppSettings.accentColorValues)
                                Semantics(
                                  button: true,
                                  selected: _settings.accentColorValue == value,
                                  label: 'Accent colour',
                                  child: InkWell(
                                    onTap: () => _settings.setAccentColor(value),
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _settings.accentColorValue == value
                                              ? Theme.of(context).colorScheme.primary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(value),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('Artwork corner radius')),
                              Text('${(_pendingThumbnailCornerRadius ?? _settings.thumbnailCornerRadius).round()} dp'),
                            ],
                          ),
                          Slider(
                            min: 0,
                            max: 45,
                            divisions: 45,
                            value: (_pendingThumbnailCornerRadius ?? _settings.thumbnailCornerRadius).clamp(0.0, 45.0).toDouble(),
                            onChanged: (value) => setState(() => _pendingThumbnailCornerRadius = value),
                            onChangeEnd: (value) async {
                              setState(() => _pendingThumbnailCornerRadius = null);
                              await _settings.setThumbnailCornerRadius(value);
                            },
                          ),
                          Text(
                            'Applies to music lists, mini-player and Now Playing artwork.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.restart_alt_rounded),
                      title: const Text('Reset appearance'),
                      subtitle: const Text('Restore default theme and visual effects'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _resetAppearance,
                    ),
                  ]),
                if (widget.category == 'Dashboard & Shortcuts')
                  _section('Dashboard & Shortcuts', [
                    SwitchListTile(
                      secondary: const Icon(Icons.dashboard_customize_rounded),
                      title: const Text('Quick actions'),
                      subtitle: const Text('Show the quick-action grid on Home'),
                      value: _settings.showQuickActions,
                      onChanged: (value) => _settings.setHomeSections(quickActions: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.grid_view_rounded),
                      title: const Text('Continue browsing'),
                      subtitle: const Text('Show recently opened folders, files and tracks on Home'),
                      value: _settings.showLibrary,
                      onChanged: (value) => _settings.setHomeSections(library: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.history_rounded),
                      title: const Text('Recent files'),
                      value: _settings.showRecentFiles,
                      onChanged: (value) => _settings.setHomeSections(recentFiles: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.search_rounded),
                      title: const Text('Global search'),
                      subtitle: const Text('Show search entry on Home'),
                      value: _settings.showGlobalSearch,
                      onChanged: (value) => _settings.setHomeSections(globalSearch: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.storage_rounded),
                      title: const Text('Storage & host health'),
                      subtitle: const Text('Show mounted volumes, device health and media scan status'),
                      value: _settings.showStorageOverview,
                      onChanged: (value) => _settings.setHomeSections(storageOverview: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.swap_vert_rounded),
                      title: const Text('Active transfers'),
                      subtitle: const Text('Show live upload and download progress on Home'),
                      value: _settings.showActiveTransfers,
                      onChanged: (value) => _settings.setHomeSections(activeTransfers: value),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.reorder_rounded),
                      title: const Text('Customize Home'),
                      subtitle: const Text('Choose visible sections and drag to change their order'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _customizeDashboardOrder,
                    ),
                  ]),
                if (widget.category == 'Discover')
                  _section('Discover Customisation', [
                    SwitchListTile(
                      secondary: const Icon(Icons.explore_rounded),
                      title: const Text('Enable Discover'),
                      subtitle: const Text('Show YouTube Music Discover in Explore'),
                      value: _settings.discoverEnabled,
                      onChanged: (value) => _settings.setDiscoverOptions(enabled: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.high_quality_rounded),
                      title: const Text('Local lossless matching'),
                      subtitle: const Text('Prefer matching FLAC, ALAC, WAV and other lossless files'),
                      value: _settings.discoverLocalLossless,
                      onChanged: (value) => _settings.setDiscoverOptions(localLossless: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.lyrics_rounded),
                      title: const Text('Lyrics'),
                      subtitle: const Text('Show synced or plain lyrics when available'),
                      value: _settings.discoverLyrics,
                      onChanged: (value) => _settings.setDiscoverOptions(lyrics: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.queue_music_rounded),
                      title: const Text('Auto-queue remaining results'),
                      subtitle: const Text('Resolve the loaded Discover list progressively after playback starts'),
                      value: _settings.discoverAutoQueue,
                      onChanged: (value) => _settings.setDiscoverOptions(autoQueue: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.image_outlined),
                      title: const Text('Show artwork'),
                      subtitle: const Text('Display YouTube Music thumbnails in Discover'),
                      value: _settings.discoverArtwork,
                      onChanged: (value) => _settings.setDiscoverOptions(artwork: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.view_carousel_rounded),
                      title: const Text('Spotlight carousel'),
                      subtitle: const Text('Show the full-width featured hero and Speed Dial page at the top of Discover'),
                      value: _settings.discoverSpotlight,
                      onChanged: (value) => _settings.setDiscoverOptions(spotlight: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.animation_rounded),
                      title: const Text('Discover Animations'),
                      subtitle: const Text('Enable animated hero transitions and staggered Discover content reveals'),
                      value: _settings.discoverMotion,
                      onChanged: _settings.setDiscoverMotion,
                    ),
                    ListTile(
                      leading: const Icon(Icons.speed_rounded),
                      title: const Text('Animation speed'),
                      subtitle: const Text('Adjust the speed of Discover hero and shelf motion'),
                      trailing: DropdownButton<String>(
                        value: _settings.discoverMotionSpeed,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'fast', child: Text('Fast')),
                          DropdownMenuItem(value: 'normal', child: Text('Normal')),
                          DropdownMenuItem(value: 'slow', child: Text('Slow')),
                        ],
                        onChanged: _settings.discoverMotion
                            ? (value) {
                                if (value != null) _settings.setDiscoverMotionSpeed(value);
                              }
                            : null,
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.grid_view_rounded),
                      title: const Text('Artist grid layout'),
                      subtitle: const Text('Optional two-column grid; off by default to match the horizontal artist shelves'),
                      value: _settings.discoverArtistGrid,
                      onChanged: (value) => _settings.setDiscoverOptions(artistGrid: value),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.graphic_eq_rounded),
                      title: const Text('Audio quality'),
                      subtitle: const Text('Balanced targets 160 kbps; Data saver targets 96 kbps when available.'),
                      trailing: DropdownButton<String>(
                        value: _settings.discoverAudioQuality,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'best_available', child: Text('Best available')),
                          DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
                          DropdownMenuItem(value: 'data_saver', child: Text('Data saver')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _settings.setDiscoverPlaybackOptions(audioQuality: value);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.route_rounded),
                      title: const Text('Resolver profile'),
                      subtitle: const Text('Choose which stream resolver is tried first'),
                      trailing: DropdownButton<String>(
                        value: _settings.discoverResolverProfile,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'automatic', child: Text('Automatic')),
                          DropdownMenuItem(value: 'newpipe_first', child: Text('NewPipe first')),
                          DropdownMenuItem(value: 'player_api_first', child: Text('Player API first')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _settings.setDiscoverPlaybackOptions(resolverProfile: value);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.playlist_add_rounded),
                      title: const Text('Import / export playlists'),
                      subtitle: const Text('Import YouTube Music, Spotify, CSV or M3U playlists and export your Discover collection'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openDiscoverPlaylists,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: const Text('Content region'),
                      subtitle: const Text('Changes YouTube Music catalogue and playback region'),
                      trailing: DropdownButton<String>(
                        value: _settings.discoverRegion,
                        underline: const SizedBox.shrink(),
                        items: AppSettings.discoverRegions.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            _settings.setDiscoverPlaybackOptions(region: value);
                          }
                        },
                      ),
                    ),
                  ]),
                if (widget.category == 'Storage')
                  _section('Storage & Downloads', [
                    FutureBuilder<String>(
                      future: DownloadManagerService.instance.defaultDirectory(),
                      builder: (context, snapshot) => ListTile(
                        leading: const Icon(Icons.folder_open_rounded),
                        title: const Text('Download location'),
                        subtitle: Text(
                          _settings.downloadDirectory ??
                              snapshot.data ??
                              'Loading system Downloads folder…',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: _chooseDownloadDirectory,
                          child: const Text('Change'),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(
                        'Downloads',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const ListTile(
                      leading: Icon(Icons.speed_rounded),
                      title: Text('Concurrent downloads'),
                      subtitle: Text('Maximum simultaneous HTTP downloads'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                            ButtonSegment(value: 5, label: Text('5')),
                          ],
                          selected: {_settings.downloadConcurrency},
                          onSelectionChanged: (values) => _settings.setDownloadOptions(
                            concurrency: values.first,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.wifi_rounded),
                      title: const Text('Wi-Fi only'),
                      subtitle: const Text('Hold downloads while connected to mobile data'),
                      value: _settings.downloadWifiOnly,
                      onChanged: (value) => _settings.setDownloadOptions(wifiOnly: value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.restart_alt_rounded),
                      title: const Text('Auto-resume on launch'),
                      subtitle: const Text('Resume unfinished downloads when PocketLink opens'),
                      value: _settings.downloadAutoResume,
                      onChanged: (value) => _settings.setDownloadOptions(autoResume: value),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_rounded),
                      title: const Text('Clear cache'),
                      subtitle: const Text('Remove temporary files and cached images'),
                      trailing: _clearingCache
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: _clearingCache ? null : _clearCache,
                    ),
                  ]),
                  if (widget.category == 'Network')
                    _section('Server Connections', [
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Saved servers'),
                        subtitle: const Text('Manage and switch PocketLink connections'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: widget.onOpenSavedServers,
                      ),
                    ]),
                  if (widget.category == 'Diagnostics')
                    _section('Diagnostics', [
                      ListTile(
                        leading: const Icon(Icons.bug_report_outlined),
                        title: const Text('Export diagnostic logs'),
                        subtitle: const Text('Generate and share the app troubleshooting log'),
                        trailing: _exportingLogs
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.ios_share_rounded),
                        onTap: _exportingLogs ? null : _exportLogs,
                      ),
                    ]),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
