import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'settings_theme_mode';
  static const _downloadKey = 'settings_download_directory';
  static const _quickActionsKey = 'settings_home_quick_actions';
  static const _libraryKey = 'settings_home_library';
  static const _recentKey = 'settings_home_recent';
  static const _liquidGlassKey = 'settings_use_liquid_glass';
  static const _navigationOrderKey = 'settings_navigation_order';
  static const _navigationVisibilityKey = 'settings_navigation_visibility';
  static const navigationDefaults = <String>['home', 'explore', 'files', 'browse'];

  ThemeMode _themeMode = ThemeMode.system;
  bool _amoled = false;
  String? _downloadDirectory;
  bool _showQuickActions = true;
  bool _showLibrary = true;
  bool _showRecentFiles = true;
  bool _useLiquidGlass = false;
  bool _loaded = false;
  List<String> _navigationOrder = List.of(navigationDefaults);
  Set<String> _visibleNavigationItems = Set.of(navigationDefaults);

  ThemeMode get themeMode => _themeMode;
  bool get amoled => _amoled;
  String? get downloadDirectory => _downloadDirectory;
  bool get showQuickActions => _showQuickActions;
  bool get showLibrary => _showLibrary;
  bool get showRecentFiles => _showRecentFiles;
  bool get useLiquidGlass => _useLiquidGlass;
  List<String> get navigationOrder => List.unmodifiable(_navigationOrder);
  Set<String> get visibleNavigationItems => Set.unmodifiable(_visibleNavigationItems);
  bool get navigationLayoutIsDefault => _navigationOrder.join(',') == navigationDefaults.join(',') && _visibleNavigationItems.length == navigationDefaults.length;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _useLiquidGlass = preferences.getBool(_liquidGlassKey) ?? false;
      final rawOrder = preferences.getString(_navigationOrderKey);
      final rawVisibility = preferences.getString(_navigationVisibilityKey);
      if (rawOrder != null) {
        final decoded = jsonDecode(rawOrder);
        if (decoded is List) {
          final values = decoded.whereType<String>().toList();
          if (values.length == navigationDefaults.length &&
              values.toSet().length == navigationDefaults.length &&
              values.toSet().containsAll(navigationDefaults) &&
              values.first == 'home') {
            _navigationOrder = values;
          }
        }
      }
      if (rawVisibility != null) {
        final decoded = jsonDecode(rawVisibility);
        if (decoded is List) {
          final values = decoded.whereType<String>().toSet();
          if (values.contains('home') && values.length >= 2 &&
              values.every(navigationDefaults.contains)) {
            _visibleNavigationItems = values;
          }
        }
      }
    } catch (_) {
      // Keep the default glass appearance if preferences are unavailable.
    }
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
      _downloadDirectory = values[1];
      _showQuickActions = values[2] != 'false';
      _showLibrary = values[3] != 'false';
      _showRecentFiles = values[4] != 'false';
    } catch (_) {
      // Keep safe defaults when secure settings storage is unavailable.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setNavigationLayout({
    required List<String> order,
    required Set<String> visibleItems,
  }) async {
    if (order.length != navigationDefaults.length ||
        order.toSet().length != navigationDefaults.length ||
        !order.toSet().containsAll(navigationDefaults) ||
        order.first != 'home' ||
        !visibleItems.contains('home') ||
        visibleItems.length < 2 ||
        !visibleItems.every(navigationDefaults.contains)) {
      throw ArgumentError('Invalid navigation layout');
    }
    _navigationOrder = List.of(order);
    _visibleNavigationItems = Set.of(visibleItems);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_navigationOrderKey, jsonEncode(_navigationOrder)),
      preferences.setString(_navigationVisibilityKey, jsonEncode(
        navigationDefaults.where(_visibleNavigationItems.contains).toList(),
      )),
    ]);
  }

  Future<void> resetNavigationLayout() async {
    _navigationOrder = List.of(navigationDefaults);
    _visibleNavigationItems = Set.of(navigationDefaults);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_navigationOrderKey),
      preferences.remove(_navigationVisibilityKey),
    ]);
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

  Future<void> setUseLiquidGlass(bool value) async {
    _useLiquidGlass = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_liquidGlassKey, value);
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
