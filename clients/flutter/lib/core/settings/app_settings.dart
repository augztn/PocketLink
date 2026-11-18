import 'dart:convert';

import 'package:material_ui/material_ui.dart';
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
  static const _homeSearchKey = 'settings_home_search';
  static const _homeTransfersKey = 'settings_home_transfers';
  static const _homeSectionOrderKey = 'settings_home_section_order';
  static const _floatingShortcutEnabledKey = 'settings_floating_shortcut_enabled';
  static const _floatingShortcutsKey = 'settings_floating_shortcuts';
  static const _floatingShortcutTapActionKey = 'settings_floating_shortcut_tap_action';
  static const _floatingShortcutLongPressKey = 'settings_floating_shortcut_long_press';
  static const _nowPlayingMiniPlayerKey = 'settings_now_playing_mini_player';
  static const _nowPlayingGesturesKey = 'settings_now_playing_gestures';
  static const _nowPlayingStatsForNerdsKey = 'settings_now_playing_stats_for_nerds';
  static const homeSectionDefaults = <String>['search', 'quick', 'transfers', 'continue', 'recent'];
  static const navigationDefaults = <String>['home', 'explore', 'files', 'browse'];
  static const floatingShortcutDefaults = <String>[
    'explore', 'music', 'files', 'videos', 'photos', 'documents',
  ];
  static const floatingShortcutDestinations = <String>{
    'explore', 'files', 'music', 'videos', 'photos', 'documents', 'favorites', 'upload',
  };

  ThemeMode _themeMode = ThemeMode.system;
  bool _amoled = false;
  String? _downloadDirectory;
  bool _showQuickActions = true;
  bool _showLibrary = true;
  bool _showRecentFiles = true;
  bool _showGlobalSearch = true;
  bool _showActiveTransfers = true;
  List<String> _homeSectionOrder = List.of(homeSectionDefaults);
  bool _useLiquidGlass = false;
  bool _loaded = false;
  List<String> _navigationOrder = List.of(navigationDefaults);
  Set<String> _visibleNavigationItems = Set.of(navigationDefaults);
  Future<void> _navigationWrite = Future<void>.value();
  bool _floatingShortcutEnabled = false;
  String _floatingShortcutTapAction = 'menu';
  bool _floatingShortcutLongPressEnabled = true;
  List<String> _floatingShortcuts = List.of(floatingShortcutDefaults);
  Future<void> _floatingShortcutsWrite = Future<void>.value();
  bool _showMiniPlayer = true;
  bool _enableNowPlayingGestures = true;
  bool _showStatsForNerds = true;

  ThemeMode get themeMode => _themeMode;
  bool get amoled => _amoled;
  String? get downloadDirectory => _downloadDirectory;
  bool get showQuickActions => _showQuickActions;
  bool get showLibrary => _showLibrary;
  bool get showRecentFiles => _showRecentFiles;
  bool get showGlobalSearch => _showGlobalSearch;
  bool get showActiveTransfers => _showActiveTransfers;
  List<String> get homeSectionOrder => List.unmodifiable(_homeSectionOrder);
  bool get useLiquidGlass => _useLiquidGlass;
  List<String> get navigationOrder => List.unmodifiable(_navigationOrder);
  Set<String> get visibleNavigationItems => Set.unmodifiable(_visibleNavigationItems);
  bool get navigationLayoutIsDefault => _navigationOrder.join(',') == navigationDefaults.join(',') && _visibleNavigationItems.length == navigationDefaults.length;
  bool get floatingShortcutEnabled => _floatingShortcutEnabled;
  String get floatingShortcutTapAction => _floatingShortcutTapAction;
  bool get floatingShortcutLongPressEnabled => _floatingShortcutLongPressEnabled;
  List<String> get floatingShortcuts => List.unmodifiable(_floatingShortcuts);
  bool get showMiniPlayer => _showMiniPlayer;
  bool get enableNowPlayingGestures => _enableNowPlayingGestures;
  bool get showStatsForNerds => _showStatsForNerds;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _useLiquidGlass = preferences.getBool(_liquidGlassKey) ?? false;
      _showMiniPlayer = preferences.getBool(_nowPlayingMiniPlayerKey) ?? false;
      _enableNowPlayingGestures = preferences.getBool(_nowPlayingGesturesKey) ?? true;
      _showStatsForNerds = preferences.getBool(_nowPlayingStatsForNerdsKey) ?? true;
      _floatingShortcutEnabled = preferences.getBool(_floatingShortcutEnabledKey) ?? false;
      final tapAction = preferences.getString(_floatingShortcutTapActionKey);
      _floatingShortcutTapAction = tapAction == 'primary' ? 'primary' : 'menu';
      _floatingShortcutLongPressEnabled = preferences.getBool(_floatingShortcutLongPressKey) ?? true;
      final rawFloatingShortcuts = preferences.getString(_floatingShortcutsKey);
      if (rawFloatingShortcuts != null) {
        final decoded = jsonDecode(rawFloatingShortcuts);
        if (decoded is List) {
          final values = decoded.whereType<String>().toList();
          if (values.isNotEmpty && values.length == decoded.length &&
              values.toSet().length == values.length &&
              values.every(floatingShortcutDestinations.contains)) {
            _floatingShortcuts = values;
          }
        }
      }
      _showGlobalSearch = preferences.getBool(_homeSearchKey) ?? true;
      _showActiveTransfers = preferences.getBool(_homeTransfersKey) ?? true;
      final rawSectionOrder = preferences.getString(_homeSectionOrderKey);
      if (rawSectionOrder != null) {
        final decoded = jsonDecode(rawSectionOrder);
        if (decoded is List) {
          final values = decoded.whereType<String>().toList();
          if (values.length == homeSectionDefaults.length &&
              values.toSet().length == homeSectionDefaults.length &&
              values.toSet().containsAll(homeSectionDefaults)) {
            _homeSectionOrder = values;
          }
        }
      }
      final rawOrder = preferences.getString(_navigationOrderKey);
      final rawVisibility = preferences.getString(_navigationVisibilityKey);
      if (rawOrder != null) {
        final decoded = jsonDecode(rawOrder);
        if (decoded is List) {
          final values = decoded.whereType<String>().toList();
          if (values.length == navigationDefaults.length &&
              values.toSet().length == navigationDefaults.length &&
              values.toSet().containsAll(navigationDefaults)) {
            _navigationOrder = values;
          }
        }
      }
      if (rawVisibility != null) {
        final decoded = jsonDecode(rawVisibility);
        if (decoded is List) {
          final values = decoded.whereType<String>().toSet();
          if (values.contains('home') &&
              values.length >= 2 &&
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
        !visibleItems.contains('home') ||
        visibleItems.length < 2 ||
        !visibleItems.every(navigationDefaults.contains)) {
      throw ArgumentError('Invalid navigation layout');
    }
    _navigationOrder = List.of(order);
    _visibleNavigationItems = Set.of(visibleItems);
    notifyListeners();
    final orderSnapshot = List<String>.of(_navigationOrder);
    final visibilitySnapshot = navigationDefaults
        .where(_visibleNavigationItems.contains)
        .toList(growable: false);
    final write = _navigationWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.setString(_navigationOrderKey, jsonEncode(orderSnapshot)),
        preferences.setString(_navigationVisibilityKey, jsonEncode(visibilitySnapshot)),
      ]);
    });
    _navigationWrite = write;
    await write;
  }

  Future<void> resetNavigationLayout() async {
    _navigationOrder = List.of(navigationDefaults);
    _visibleNavigationItems = Set.of(navigationDefaults);
    notifyListeners();
    final write = _navigationWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(_navigationOrderKey),
        preferences.remove(_navigationVisibilityKey),
      ]);
    });
    _navigationWrite = write;
    await write;
  }

  Future<void> setFloatingShortcutEnabled(bool enabled) async {
    _floatingShortcutEnabled = enabled;
    notifyListeners();
    final write = _floatingShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_floatingShortcutEnabledKey, enabled);
    });
    _floatingShortcutsWrite = write;
    await write;
  }

  Future<void> setFloatingShortcutTapAction(String action) async {
    if (action != 'primary' && action != 'menu') {
      throw ArgumentError.value(action, 'action', 'Unsupported floating shortcut tap action');
    }
    _floatingShortcutTapAction = action;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_floatingShortcutTapActionKey, action);
  }

  Future<void> setFloatingShortcutLongPressEnabled(bool enabled) async {
    _floatingShortcutLongPressEnabled = enabled;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_floatingShortcutLongPressKey, enabled);
  }

  Future<void> setFloatingShortcuts(List<String> shortcuts) async {
    if (shortcuts.isEmpty ||
        shortcuts.toSet().length != shortcuts.length ||
        !shortcuts.every(floatingShortcutDestinations.contains)) {
      throw ArgumentError('Invalid floating shortcuts');
    }
    _floatingShortcuts = List.of(shortcuts);
    notifyListeners();
    final snapshot = List<String>.of(_floatingShortcuts);
    final write = _floatingShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_floatingShortcutsKey, jsonEncode(snapshot));
    });
    _floatingShortcutsWrite = write;
    await write;
  }

  Future<void> resetFloatingShortcuts() async {
    _floatingShortcuts = List.of(floatingShortcutDefaults);
    notifyListeners();
    final write = _floatingShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(_floatingShortcutsKey),
      ]);
    });
    _floatingShortcutsWrite = write;
    await write;
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

  Future<void> setNowPlayingOptions({
    bool? miniPlayer,
    bool? gestures,
    bool? statsForNerds,
  }) async {
    if (miniPlayer != null) _showMiniPlayer = miniPlayer;
    if (gestures != null) _enableNowPlayingGestures = gestures;
    if (statsForNerds != null) _showStatsForNerds = statsForNerds;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (miniPlayer != null) preferences.setBool(_nowPlayingMiniPlayerKey, miniPlayer),
      if (gestures != null) preferences.setBool(_nowPlayingGesturesKey, gestures),
      if (statsForNerds != null) preferences.setBool(_nowPlayingStatsForNerdsKey, statsForNerds),
    ]);
  }

  Future<void> resetNowPlayingOptions() async {
    _showMiniPlayer = true;
    _enableNowPlayingGestures = true;
    _showStatsForNerds = true;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_nowPlayingMiniPlayerKey),
      preferences.remove(_nowPlayingGesturesKey),
      preferences.remove(_nowPlayingStatsForNerdsKey),
    ]);
  }

  Future<void> setUseLiquidGlass(bool value) async {
    _useLiquidGlass = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_liquidGlassKey, value);
  }

  Future<void> setHomeSectionOrder(List<String> order) async {
    if (order.length != homeSectionDefaults.length ||
        order.toSet().length != homeSectionDefaults.length ||
        !order.toSet().containsAll(homeSectionDefaults)) {
      throw ArgumentError('Invalid Home section order');
    }
    _homeSectionOrder = List.of(order);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_homeSectionOrderKey, jsonEncode(_homeSectionOrder));
  }

  Future<void> setHomeSections({
    bool? quickActions,
    bool? library,
    bool? recentFiles,
    bool? globalSearch,
    bool? activeTransfers,
  }) async {
    if (quickActions != null) _showQuickActions = quickActions;
    if (library != null) _showLibrary = library;
    if (recentFiles != null) _showRecentFiles = recentFiles;
    if (globalSearch != null) _showGlobalSearch = globalSearch;
    if (activeTransfers != null) _showActiveTransfers = activeTransfers;
    notifyListeners();
    await Future.wait([
      if (quickActions != null) _storage.write(key: _quickActionsKey, value: '$quickActions'),
      if (library != null) _storage.write(key: _libraryKey, value: '$library'),
      if (recentFiles != null) _storage.write(key: _recentKey, value: '$recentFiles'),
    ]);
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (globalSearch != null) preferences.setBool(_homeSearchKey, globalSearch),
      if (activeTransfers != null) preferences.setBool(_homeTransfersKey, activeTransfers),
    ]);
  }
}
