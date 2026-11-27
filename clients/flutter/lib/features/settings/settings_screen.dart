import 'dart:io';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/server_api.dart';
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
  const SettingsScreen({this.api, this.onOpenSavedServers, this.category, super.key});

  final ServerApi? api;

  final VoidCallback? onOpenSavedServers;
  final String? category;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettings.instance;
  bool _clearingCache = false;
  bool _exportingLogs = false;
  bool _exportingSettings = false;
  bool _importingSettings = false;
  String _settingsSearchQuery = '';
  final TextEditingController _settingsSearchController = TextEditingController();

  Future<void> _openDiscoverPlaylists() async {
    final api = widget.api;
    if (api == null) {
      _message('Connect to your PocketLink server to manage Discover playlists.');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => ImportedPlaylistManagerScreen(api: api),
    ));
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

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionHeader(title),
            SettingsGroupCard(children: children),
          ],
        ),
      );

  String _pageTitle(String? category) => switch (category) {
        'Appearance' => 'Appearance',
        'Navigation' => 'Navigation',
        'Music' => 'Music & Playback',
        'Dashboard & Shortcuts' => 'Dashboard',
        'Connectivity' => 'Network',
        'Maintenance' => 'Diagnostics',
        'Music / Now Playing Button' => 'Music & Player',
        'Customize Navigation Bar' => 'Navigation',
        _ => category ?? 'Settings',
      };

  // Diagnostic isolation: Settings category routes temporarily bypass the
  // app-wide custom PageTransitionsTheme. If the pop hesitation disappears,
  // the category route transition is implicated; other app routes are unchanged.
  PageRoute<void> _categoryRoute(WidgetBuilder builder) => PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  void _openCategory(String id) {
    final route = switch (id) {
      'navigation-customize' => _categoryRoute(
          (_) => const NavigationCustomizationScreen(),
        ),
      'audio' => _categoryRoute(
          (_) => const NowPlayingSettingsScreen(),
        ),
      'video' => _categoryRoute(
          (_) => const VideoPlayerSettingsScreen(),
        ),
      'about' => _categoryRoute((_) => const AboutScreen()),
      _ => _categoryRoute(
          (_) => SettingsScreen(
            api: widget.api,
            onOpenSavedServers: widget.onOpenSavedServers,
            category: switch (id) {
              'appearance' => 'Appearance',
              'navigation' => 'Navigation',
              'dashboard' => 'Dashboard & Shortcuts',
              'music' => 'Music',
              'discover' => 'Discover',
              'storage' => 'Storage',
              'network' || 'connectivity' => 'Connectivity',
              'diagnostics' || 'maintenance' => 'Maintenance',
              _ => 'Connectivity',
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
        'Theme mode': 'theme light dark system brightness',
        'AMOLED mode': 'amoled oled black deep black',
        'Liquid Glass UI': 'liquid glass frosted reflections surfaces',
        'Progressive Blur': 'progressive blur shader fade header',
        'Live preview': 'preview sample appearance',
        'Reset appearance': 'reset defaults restore theme',
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
        'Clear cache': 'temporary files image cache clear',
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
      'navigation': 'navigation bar dock dashboard home fab',
      'storage': 'storage downloads files transfers',
      'music': 'music audio playback discover video lyrics playlists',
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

  Future<void> _resetAppearance() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset appearance settings?'),
        content: const Text(
          'Restore System theme, disable AMOLED mode, turn Liquid Glass off, and restore Progressive Blur to its default. Other settings will not change.',
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
    await _settings.setUseLiquidGlass(false);
    await _settings.setProgressiveBlurEnabled(true);
    if (mounted) _message('Appearance settings restored to defaults.');
  }

  Widget _categoryIntro(String category) {
    final descriptions = <String, String>{
      'Appearance': 'Theme, OLED black mode, blur, colors and visual effects.',
      'Navigation': 'Dock, destinations, dashboard sections and floating shortcuts.',
      'Music': 'Music library, playback, Discover, lyrics and video preferences.',
      'Storage': 'Volumes, downloads, transfer behavior and temporary cache.',
      'Connectivity': 'Manage saved PocketLink servers and connection switching.',
      'Maintenance': 'Back up settings, restore preferences and export diagnostic logs.',
      'Dashboard & Shortcuts': 'Choose which Home sections appear and arrange their order.',
      'Discover': 'Configure music discovery, matching, playback preferences and playlists.',
      'Storage': 'Manage download location, transfer behavior and temporary cache.',
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
    Padding(
      padding: const EdgeInsets.only(bottom: 18),
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
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ),
    if (_categoryMatches('appearance') || _categoryMatches('navigation'))
      _settingsGroupTitle('Personalization'),
    if (_categoryMatches('appearance'))
      _categoryTile(
        id: 'appearance',
        icon: Icons.palette_rounded,
        tint: const Color(0xFF8D72E8),
        title: 'Appearance',
        subtitle: 'Theme, blur, OLED black mode and colors',
        badge: _settings.amoled
            ? 'AMOLED'
            : _settings.themeMode == ThemeMode.dark
                ? 'Dark'
                : _settings.themeMode == ThemeMode.light
                    ? 'Light'
                    : 'System',
      ),
    if (_categoryMatches('navigation'))
      _categoryTile(
        id: 'navigation',
        icon: Icons.tune_rounded,
        tint: const Color(0xFF60A5FA),
        title: 'Navigation',
        subtitle: 'Dock, FAB, dashboard sections and shortcuts',
        badge: '${_settings.visibleNavigationItems.length} tabs',
      ),
    if (_categoryMatches('storage') || _categoryMatches('music'))
      _settingsGroupTitle('Storage & Media'),
    if (_categoryMatches('storage'))
      _categoryTile(
        id: 'storage',
        icon: Icons.storage_rounded,
        tint: const Color(0xFFFBBF24),
        title: 'Storage',
        subtitle: 'Volumes, downloads, transfers and cache',
        badge: '${_settings.downloadConcurrency} concurrent',
      ),
    if (_categoryMatches('music'))
      _categoryTile(
        id: 'music',
        icon: Icons.graphic_eq_rounded,
        tint: const Color(0xFFDB79A8),
        title: 'Music',
        subtitle: 'Library, playback, Discover, lyrics and video',
        badge: _settings.discoverEnabled ? 'Discover On' : 'Discover Off',
      ),
    if (_categoryMatches('network') || _categoryMatches('diagnostics') || _categoryMatches('about'))
      _settingsGroupTitle('Network & System'),
    if (_categoryMatches('network'))
      _categoryTile(
        id: 'network',
        icon: Icons.wifi_rounded,
        tint: const Color(0xFF4ADE80),
        title: 'Network',
        subtitle: 'Saved servers and connection settings',
        badge: 'Manage',
      ),
    if (_categoryMatches('diagnostics'))
      _categoryTile(
        id: 'diagnostics',
        icon: Icons.build_circle_outlined,
        tint: const Color(0xFF60A5FA),
        title: 'Diagnostics',
        subtitle: 'Backups, restore, logs and troubleshooting',
        badge: 'Tools',
      ),
    if (_categoryMatches('about'))
      _categoryTile(
        id: 'about',
        icon: Icons.info_outline_rounded,
        tint: const Color(0xFFFBBF24),
        title: 'About PocketLink',
        subtitle: 'Version information, architecture and licenses',
        badge: 'Info',
      ),
    if (!_categoryMatches('appearance') &&
        !_categoryMatches('navigation') &&
        !_categoryMatches('storage') &&
        !_categoryMatches('music') &&
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
    required String subtitle,
    String? badge,
  }) {
    final colors = Theme.of(context).colorScheme;
    final matches = _matchingSettingLabels(id);
    final query = _settingsSearchQuery.trim();
    final visibleSubtitle = query.isEmpty || matches.isEmpty
        ? subtitle
        : '$subtitle · Matches: ${matches.join(', ')}';
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final progress = MediaQuery.of(context).disableAnimations ? 1.0 : value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - progress)),
            child: Transform.scale(
              scale: 0.985 + (0.015 * progress),
              child: child,
            ),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: colors.surfaceContainerLow,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.56),
          ),
        ),
        child: InkWell(
          onTap: () => _openCategory(id),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: tint, size: 23),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        visibleSubtitle,
                        maxLines: query.isEmpty ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tint,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ],
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
        appBar: PocketLinkAppBar(
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
                ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            topClearance,
            16,
            bottomClearance,
          ),
          children: widget.category == null
              ? _homeSettingsChildren()
              : [
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
                if (widget.category == 'Maintenance')
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
                if (widget.category == 'Appearance')
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
                  if (widget.category == 'Connectivity')
                    _section('Server Connections', [
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Saved servers'),
                        subtitle: const Text('Manage and switch PocketLink connections'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: widget.onOpenSavedServers,
                      ),
                    ]),
                  if (widget.category == 'Maintenance')
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
              ],
            );
          },
        ),
      ),
    );
  }
}
