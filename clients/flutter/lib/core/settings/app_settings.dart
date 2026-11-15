import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'settings_theme_mode';
  static const _downloadKey = 'settings_download_directory';
  static const _quickActionsKey = 'settings_home_quick_actions';
  static const _libraryKey = 'settings_home_library';
  static const _recentKey = 'settings_home_recent';

  ThemeMode _themeMode = ThemeMode.system;
  bool _amoled = false;
  String? _downloadDirectory;
  bool _showQuickActions = true;
  bool _showLibrary = true;
  bool _showRecentFiles = true;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get amoled => _amoled;
  String? get downloadDirectory => _downloadDirectory;
  bool get showQuickActions => _showQuickActions;
  bool get showLibrary => _showLibrary;
  bool get showRecentFiles => _showRecentFiles;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final values = await Future.wait([
        _storage.read(key: _themeKey),
        _storage.read(key: _downloadKey),
        _storage.read(key: _quickActionsKey),
        _storage.read(key: _libraryKey),
        _storage.read(key: _recentKey),
      ]);
      _themeMode = switch (values[0]) {
        'light' => ThemeMode.light,
        'dark' || 'amoled' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _amoled = values[0] == 'amoled';
    _streamingQuality = const {'Data saver', 'Balanced', 'Original'}.contains(values[1])
        ? values[1]!
        : 'Original';
    _downloadDirectory = values[2];
    _showQuickActions = values[3] != 'false';
    _showLibrary = values[4] != 'false';
      _showRecentFiles = values[5] != 'false';
    } catch (_) {
      // Keep safe defaults when secure settings storage is unavailable.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    _amoled = false;
    notifyListeners();
    await _storage.write(key: _themeKey, value: switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setAmoled(bool value) async {
    _amoled = value;
    if (value) _themeMode = ThemeMode.dark;
    notifyListeners();
    await _storage.write(key: _themeKey, value: value ? 'amoled' : 'dark');
  }

  Future<void> setDownloadDirectory(String? value) async {
    _downloadDirectory = value;
    notifyListeners();
    if (value == null) {
      await _storage.delete(key: _downloadKey);
    } else {
      await _storage.write(key: _downloadKey, value: value);
    }
  }

  Future<void> setHomeSections({
    bool? quickActions,
    bool? library,
    bool? recentFiles,
  }) async {
    if (quickActions != null) _showQuickActions = quickActions;
    if (library != null) _showLibrary = library;
    if (recentFiles != null) _showRecentFiles = recentFiles;
    notifyListeners();
    await Future.wait([
      if (quickActions != null) _storage.write(key: _quickActionsKey, value: '$quickActions'),
      if (library != null) _storage.write(key: _libraryKey, value: '$library'),
      if (recentFiles != null) _storage.write(key: _recentKey, value: '$recentFiles'),
    ]);
  }
}
