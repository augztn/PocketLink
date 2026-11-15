import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.onOpenSavedServers, super.key});

  final VoidCallback? onOpenSavedServers;

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
        subject: 'HomeServer diagnostic logs',
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            _section('Appearance', [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Theme mode'),
                subtitle: Text(_settings.amoled ? 'AMOLED black' : switch (_settings.themeMode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.system => 'System default',
                }),
                trailing: DropdownButton<ThemeMode>(
                  value: _settings.themeMode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                  onChanged: (value) {
                    if (value != null) _settings.setThemeMode(value);
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('AMOLED black'),
                subtitle: const Text('Use a true-black dark background'),
                value: _settings.amoled,
                onChanged: _settings.setAmoled,
              ),
              const Divider(height: 1),
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
            ]),
            _section('Media & Storage', [
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: const Text('Streaming quality'),
                subtitle: const Text('Playback preference for supported media streams'),
                trailing: DropdownButton<String>(
                  value: _settings.streamingQuality,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'Data saver', child: Text('Data saver')),
                    DropdownMenuItem(value: 'Balanced', child: Text('Balanced')),
                    DropdownMenuItem(value: 'Original', child: Text('Original')),
                  ],
                  onChanged: (value) {
                    if (value != null) _settings.setStreamingQuality(value);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_download_outlined),
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
            _section('Connection & Diagnostics', [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Saved servers'),
                subtitle: const Text('Manage and switch HomeServer connections'),
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
