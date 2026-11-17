import 'dart:io';
import '../../core/widgets/pocketlink_app_bar.dart';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/app_settings.dart';
import 'navigation_customization_screen.dart';
import 'floating_shortcut_customization_screen.dart';
import 'now_playing_settings_screen.dart';
import '../about/about_screen.dart';

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

  Future<void> _chooseDownloadDirectory() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath();
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
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'PocketLink diagnostic logs',
        text: 'Review the diagnostic file before sharing. It may contain server addresses and filesystem error details.',
      );
      await AppLogger.info('Diagnostic log export requested from Settings');
    } catch (error, stack) {
      await AppLogger.error('Settings diagnostic export failed', error: error, stackTrace: stack);
      if (mounted) _message('Could not export diagnostic logs.');
    } finally {
      if (mounted) setState(() => _exportingLogs = false);
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

  Widget _categoryTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Icon(icon, size: 26),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => title == 'About PocketLink'
              ? const AboutScreen()
              : SettingsScreen(
                  onOpenSavedServers: widget.onOpenSavedServers,
                  category: title,
                ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => Scaffold(
        appBar: PocketLinkAppBar(title: Text(widget.category ?? 'Settings')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: widget.category == null
              ? [
                  _categoryTile(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    subtitle: 'Themes, colors, navigation and dashboard layout',
                  ),
                  _categoryTile(
                    icon: Icons.perm_media_outlined,
                    title: 'Media & Storage',
                    subtitle: 'Streaming, downloads and cached data',
                  ),
                  _categoryTile(
                    icon: Icons.wifi_rounded,
                    title: 'Connection & Diagnostics',
                    subtitle: 'Saved servers and troubleshooting logs',
                  ),
                  _categoryTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About PocketLink',
                    subtitle: 'Version, developer, source code and licenses',
                  ),
                ]
              : [
                if (widget.category == 'Appearance')
                              _section('Appearance', [
                                ListTile(
                                  leading: const Icon(Icons.palette_outlined),
                                  title: const Text('Theme mode'),
                                  subtitle: Text(_settings.amoled ? 'AMOLED black' : switch (_settings.themeMode) {
                                    ThemeMode.light => 'Light',
                                    ThemeMode.dark => 'Dark',
                                    ThemeMode.system => 'System default',
                                  }),
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
                                  subtitle: const Text('Translucent frosted blur on floating navigation and action pills'),
                                  value: _settings.useLiquidGlass,
                                  onChanged: _settings.setUseLiquidGlass,
                                ),
                                SwitchListTile(
                                  secondary: const Icon(Icons.bolt_rounded),
                                  title: const Text('Floating Quick-Shortcut Button'),
                                  subtitle: const Text('Off by default · Show a customizable quick-access button above the navigation bar'),
                                  value: _settings.floatingShortcutEnabled,
                                  onChanged: _settings.setFloatingShortcutEnabled,
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  leading: const Icon(Icons.tune_rounded),
                                  title: const Text('Customize Floating Shortcuts'),
                                  subtitle: Text('${_settings.floatingShortcuts.length} pinned destinations · tap action and press behavior'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const FloatingShortcutCustomizationScreen(),
                                    ),
                                  ),
                                ),
                                SwitchListTile(
                                  secondary: const Icon(Icons.dashboard_customize_outlined),
                                  title: const Text('Quick actions'),
                                  value: _settings.showQuickActions,
                                  onChanged: (value) => _settings.setHomeSections(quickActions: value),
                                ),
                                SwitchListTile(
                                  secondary: const Icon(Icons.grid_view_rounded),
                                  title: const Text('Your library'),
                                  value: _settings.showLibrary,
                                  onChanged: (value) => _settings.setHomeSections(library: value),
                                ),
                                SwitchListTile(
                                  secondary: const Icon(Icons.history_rounded),
                                  title: const Text('Recent files'),
                                  value: _settings.showRecentFiles,
                                  onChanged: (value) => _settings.setHomeSections(recentFiles: value),
                                ),
                                SwitchListTile(
                                  secondary: const Icon(Icons.search_rounded),
                                  title: const Text('Global search'),
                                  subtitle: const Text('Show the search entry on Home'),
                                  value: _settings.showGlobalSearch,
                                  onChanged: (value) => _settings.setHomeSections(globalSearch: value),
                                ),
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
                                const Divider(height: 1),
                                ListTile(
                                  leading: const Icon(Icons.tune_rounded),
                                  title: const Text('Customize Navigation Bar'),
                                  subtitle: const Text('Reorder or show and hide dock destinations'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const NavigationCustomizationScreen(),
                                    ),
                                  ),
                                ),
                              ]),
                  if (widget.category == 'Media & Storage')
                            _section('Media & Storage', [
                                ListTile(
                                  leading: const Icon(Icons.graphic_eq_rounded),
                                  title: const Text('Now Playing customization'),
                                  subtitle: const Text('Mini-player, artwork, controls and swipe gestures'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const NowPlayingSettingsScreen(),
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  leading: const Icon(Icons.high_quality_outlined),
                                  title: const Text('Streaming quality'),
                                  subtitle: const Text('RAW · Original source quality · No transcoding or compression'),
                                  trailing: const Chip(
                                    label: Text('ORIGINAL'),
                                    avatar: Icon(Icons.verified_rounded, size: 16),
                                  ),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: const Text('Download directory'),
                                  subtitle: Text(_settings.downloadDirectory ?? 'Use the system default'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: _chooseDownloadDirectory,
                                ),
                                ListTile(
                                  leading: const Icon(Icons.cleaning_services_outlined),
                                  title: const Text('Clear cache'),
                                  subtitle: const Text('Remove temporary files and cached images'),
                                  trailing: _clearingCache
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
      ),
    );
  }
}
