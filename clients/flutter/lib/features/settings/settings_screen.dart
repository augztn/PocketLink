import 'dart:io';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/pocketlink_scaffold.dart';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_backup_service.dart';
import 'navigation_customization_screen.dart';
import 'now_playing_settings_screen.dart';
import 'video_player_settings_screen.dart';
import '../about/about_screen.dart';
import '../downloads/download_manager_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.onOpenSavedServers, this.category, super.key});

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
    const labels = <String, String>{
      'search': 'Global search',
      'quick': 'Quick actions',
      'transfers': 'Active transfers',
      'continue': 'Continue',
      'recent': 'Recent files',
    };
    var draft = List<String>.of(_settings.homeSectionOrder);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reorder Home sections'),
          content: SizedBox(
            width: 420,
            height: 380,
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
                return ListTile(
                  key: ValueKey(id),
                  leading: const Icon(Icons.drag_handle_rounded),
                  title: Text(labels[id]!),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => setDialogState(
                () => draft = List.of(AppSettings.homeSectionDefaults),
              ),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _settings.setHomeSectionOrder(result);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          )),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    ),
  );

  Widget _settingsGroupTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 9),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
        ),
      );

  void _openCategory(String id) {
    final route = switch (id) {
      'navigation' => MaterialPageRoute<void>(
          builder: (_) => const NavigationCustomizationScreen(),
        ),
      'audio' => MaterialPageRoute<void>(
          builder: (_) => const NowPlayingSettingsScreen(),
        ),
      'video' => MaterialPageRoute<void>(
          builder: (_) => const VideoPlayerSettingsScreen(),
        ),
      'about' => MaterialPageRoute<void>(
          builder: (_) => const AboutScreen(),
        ),
      _ => MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            onOpenSavedServers: widget.onOpenSavedServers,
            category: switch (id) {
              'appearance' => 'Appearance',
              'dashboard' => 'Dashboard & Shortcuts',
              'media' => 'Media & Storage',
              'backup' => 'Backup & Restore',
              _ => 'Connection & Diagnostics',
            },
          ),
        ),
    };
    Navigator.of(context).push(route);
  }

  Widget _categoryTile({
    required String id,
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    String? badge,
  }) {
    final colors = Theme.of(context).colorScheme;
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
                        subtitle,
                        maxLines: 2,
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PocketLinkAppBar(
          title: Text(widget.category ?? 'Settings'),
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
            final bottomClearance =
                LayoutInsetsScope.of(bodyContext).bottomClearance;
            return Stack(
              children: [
                ListView(
          padding: PocketLinkHorizontalGutter.padding(bodyContext).copyWith(
            top: LayoutInsetsScope.of(bodyContext).topClearance,
            bottom: bottomClearance,
          ),
          children: widget.category == null
              ? [
                  _settingsGroupTitle('Personalization'),
                  _categoryTile(
                    id: 'appearance',
                    icon: Icons.palette_rounded,
                    tint: const Color(0xFF8D72E8),
                    title: 'Appearance & Theme',
                    subtitle: 'Themes, Liquid Glass and Progressive Blur controls',
                    badge: _settings.themeMode == ThemeMode.dark
                        ? (_settings.amoled ? 'AMOLED' : 'Dark')
                        : _settings.themeMode == ThemeMode.light
                            ? 'Light'
                            : 'System',
                  ),
                  _categoryTile(
                    id: 'navigation',
                    icon: Icons.tune_rounded,
                    tint: const Color(0xFF60A5FA),
                    title: 'Navigation Bar & Dock',
                    subtitle: 'Reorder tabs and choose which destinations appear',
                    badge: '${_settings.visibleNavigationItems.length} tabs',
                  ),
                  _categoryTile(
                    id: 'dashboard',
                    icon: Icons.dashboard_customize_rounded,
                    tint: const Color(0xFF2DD4BF),
                    title: 'Dashboard & Shortcuts',
                    subtitle: 'Home sections, quick actions and dashboard layout',
                  ),
                  _settingsGroupTitle('Media & Storage'),
                  _categoryTile(
                    id: 'audio',
                    icon: Icons.graphic_eq_rounded,
                    tint: const Color(0xFF8D72E8),
                    title: 'Audio & Now Playing',
                    subtitle: 'Music button gestures, shortcuts and mini-player',
                    badge: _settings.showMiniPlayer ? 'Mini On' : 'Mini Off',
                  ),
                  _categoryTile(
                    id: 'video',
                    icon: Icons.movie_creation_rounded,
                    tint: const Color(0xFF28B8C8),
                    title: 'Video Player',
                    subtitle: 'Playback gestures, controls, scaling and subtitles',
                  ),
                  _categoryTile(
                    id: 'media',
                    icon: Icons.perm_media_rounded,
                    tint: const Color(0xFFFBBF24),
                    title: 'Media Library & Storage',
                    subtitle: 'Download location and temporary cache',
                  ),
                  _categoryTile(
                    id: 'backup',
                    icon: Icons.backup_rounded,
                    tint: const Color(0xFF60A5FA),
                    title: 'Backup & Restore',
                    subtitle: 'Export or restore your PocketLink preferences',
                  ),
                  _settingsGroupTitle('Network & System'),
                  _categoryTile(
                    id: 'connection',
                    icon: Icons.wifi_rounded,
                    tint: const Color(0xFF4ADE80),
                    title: 'Connection & Diagnostics',
                    subtitle: 'Saved servers, connectivity help and logs',
                  ),
                  _categoryTile(
                    id: 'about',
                    icon: Icons.info_outline_rounded,
                    tint: const Color(0xFFFBBF24),
                    title: 'About PocketLink',
                    subtitle: 'Version information, architecture and licenses',
                  ),
                ]
              : [
                if (widget.category == 'Backup & Restore')
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
                    Padding(
                      padding: PocketLinkHorizontalGutter.padding(context).copyWith(top: 8, bottom: 16),
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
                  ]),
                if (widget.category == 'Appearance')
                  _section('Glass & Visual Effects', [
                    SwitchListTile(
                      secondary: const Icon(Icons.gradient_rounded),
                      title: const Text('Progressive Blur'),
                      subtitle: const Text(
                        'Blur scrolling content smoothly behind the status bar and floating headers',
                      ),
                      value: _settings.progressiveBlurEnabled,
                      onChanged: _settings.setProgressiveBlurEnabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Blur strength',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const Spacer(),
                              Text(
                                '${_settings.progressiveBlurStrength.round()}%',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            min: 0,
                            max: 100,
                            divisions: 20,
                            value: _settings.progressiveBlurStrength,
                            onChanged: _settings.progressiveBlurEnabled
                                ? _settings.setProgressiveBlurStrength
                                : null,
                          ),
                          Text(
                            'Subtle at 0% · Strong at 100%',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
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
                      title: const Text('Your library'),
                      subtitle: const Text('Show the Continue section on Home'),
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
                      secondary: const Icon(Icons.swap_vert_rounded),
                      title: const Text('Active transfers'),
                      subtitle: const Text('Show live upload and download progress on Home'),
                      value: _settings.showActiveTransfers,
                      onChanged: (value) => _settings.setHomeSections(activeTransfers: value),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.reorder_rounded),
                      title: const Text('Reorder Home sections'),
                      subtitle: const Text('Choose the order of dashboard sections'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _customizeDashboardOrder,
                    ),
                  ]),
                if (widget.category == 'Media & Storage')
                  _section('Media Library & Storage', [
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
                  if (widget.category == 'Connection & Diagnostics')
                            _section('Connection & Diagnostics', [
                                ListTile(
                                  leading: const Icon(Icons.dns_outlined),
                                  title: const Text('Saved servers'),
                                  subtitle: const Text('Manage and switch PocketLink connections'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: widget.onOpenSavedServers,
                                ),
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
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: FeatheredGlassHeaderBackground(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
