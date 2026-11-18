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
  // Keep the existing preference key so saved shortcut choices survive the cleanup.
  static const _musicButtonShortcutsKey = 'settings_floating_shortcuts';
  static const _musicButtonSwipeEnabledKey = 'settings_music_button_swipe_enabled';
  static const _musicButtonSwipeLeftActionKey = 'settings_music_button_swipe_left_action';
  static const _musicButtonSwipeRightActionKey = 'settings_music_button_swipe_right_action';
  static const _musicButtonLongPressEnabledKey = 'settings_music_button_long_press_enabled';
  static const _nowPlayingMiniPlayerKey = 'settings_now_playing_mini_player';
  static const _nowPlayingGesturesKey = 'settings_now_playing_gestures';
  static const _nowPlayingStatsForNerdsKey = 'settings_now_playing_stats_for_nerds';
  static const _videoControlsTimeoutKey = 'settings_video_controls_timeout';
  static const _videoSeekSecondsKey = 'settings_video_seek_seconds';
  static const _videoDefaultSpeedKey = 'settings_video_default_speed';
  static const _videoFitModeKey = 'settings_video_fit_mode';
  static const _videoGesturesKey = 'settings_video_gestures';
  static const _videoPinchZoomKey = 'settings_video_pinch_zoom';
  static const _videoTapToggleKey = 'settings_video_tap_toggle';
  static const _videoSubtitleFontSizeKey = 'settings_video_subtitle_font_size';
  static const _videoSubtitleBackgroundKey = 'settings_video_subtitle_background';
  static const _videoAutoFullscreenKey = 'settings_video_auto_fullscreen';
  static const _videoFullscreenOrientationKey = 'settings_video_fullscreen_orientation';
  static const homeSectionDefaults = <String>['search', 'quick', 'transfers', 'continue', 'recent'];
  static const navigationDefaults = <String>['home', 'explore', 'files', 'browse'];
  static const musicButtonShortcutDefaults = <String>[
    'photos', 'music', 'videos', 'documents', 'files', 'search', 'drives',
  ];
  static const musicButtonShortcutDestinations = <String>{
    'explore', 'files', 'music', 'videos', 'photos', 'documents', 'favorites', 'upload', 'search', 'drives',
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
  bool _musicButtonSwipeEnabled = true;
  String _musicButtonSwipeLeftAction = 'next';
  String _musicButtonSwipeRightAction = 'previous';
  bool _musicButtonLongPressEnabled = true;
  List<String> _musicButtonShortcuts = List.of(musicButtonShortcutDefaults);
  Future<void> _musicButtonShortcutsWrite = Future<void>.value();
  bool _showMiniPlayer = true;
  bool _enableNowPlayingGestures = true;
  bool _showStatsForNerds = true;
  int _videoControlsTimeoutSeconds = 4;
  int _videoSeekSeconds = 10;
  double _videoDefaultSpeed = 1.0;
  String _videoFitMode = 'contain';
  bool _videoGesturesEnabled = true;
  bool _videoPinchZoomEnabled = true;
  bool _videoTapToTogglePlayback = false;
  double _videoSubtitleFontSize = 20;
  bool _videoSubtitleBackground = true;
  bool _videoAutoFullscreen = false;
  String _videoFullscreenOrientation = 'landscape';

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
  List<String> get musicButtonShortcuts => List.unmodifiable(_musicButtonShortcuts);
  bool get musicButtonSwipeEnabled => _musicButtonSwipeEnabled;
  String get musicButtonSwipeLeftAction => _musicButtonSwipeLeftAction;
  String get musicButtonSwipeRightAction => _musicButtonSwipeRightAction;
  bool get musicButtonLongPressEnabled => _musicButtonLongPressEnabled;
  bool get showMiniPlayer => _showMiniPlayer;
  bool get enableNowPlayingGestures => _enableNowPlayingGestures;
  bool get showStatsForNerds => _showStatsForNerds;
  int get videoControlsTimeoutSeconds => _videoControlsTimeoutSeconds;
  int get videoSeekSeconds => _videoSeekSeconds;
  double get videoDefaultSpeed => _videoDefaultSpeed;
  String get videoFitMode => _videoFitMode;
  bool get videoGesturesEnabled => _videoGesturesEnabled;
  bool get videoPinchZoomEnabled => _videoPinchZoomEnabled;
  bool get videoTapToTogglePlayback => _videoTapToTogglePlayback;
  double get videoSubtitleFontSize => _videoSubtitleFontSize;
  bool get videoSubtitleBackground => _videoSubtitleBackground;
  bool get videoAutoFullscreen => _videoAutoFullscreen;
  String get videoFullscreenOrientation => _videoFullscreenOrientation;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _useLiquidGlass = preferences.getBool(_liquidGlassKey) ?? false;
      _showMiniPlayer = preferences.getBool(_nowPlayingMiniPlayerKey) ?? true;
      _enableNowPlayingGestures = preferences.getBool(_nowPlayingGesturesKey) ?? true;
      _showStatsForNerds = preferences.getBool(_nowPlayingStatsForNerdsKey) ?? true;
      _videoControlsTimeoutSeconds = preferences.getInt(_videoControlsTimeoutKey) ?? 4;
      _videoSeekSeconds = preferences.getInt(_videoSeekSecondsKey) ?? 10;
      _videoDefaultSpeed = preferences.getDouble(_videoDefaultSpeedKey) ?? 1.0;
      _videoFitMode = preferences.getString(_videoFitModeKey) ?? 'contain';
      _videoGesturesEnabled = preferences.getBool(_videoGesturesKey) ?? true;
      _videoPinchZoomEnabled = preferences.getBool(_videoPinchZoomKey) ?? true;
      _videoTapToTogglePlayback = preferences.getBool(_videoTapToggleKey) ?? false;
      _videoSubtitleFontSize = preferences.getDouble(_videoSubtitleFontSizeKey) ?? 20;
      _videoSubtitleBackground = preferences.getBool(_videoSubtitleBackgroundKey) ?? true;
      _videoAutoFullscreen = preferences.getBool(_videoAutoFullscreenKey) ?? false;
      _videoFullscreenOrientation = preferences.getString(_videoFullscreenOrientationKey) ?? 'landscape';
      _musicButtonSwipeEnabled = preferences.getBool(_musicButtonSwipeEnabledKey) ?? true;
      _musicButtonSwipeLeftAction = _validMusicSwipeAction(preferences.getString(_musicButtonSwipeLeftActionKey), 'next');
      _musicButtonSwipeRightAction = _validMusicSwipeAction(preferences.getString(_musicButtonSwipeRightActionKey), 'previous');
      _musicButtonLongPressEnabled = preferences.getBool(_musicButtonLongPressEnabledKey) ?? true;
      final rawMusicButtonShortcuts = preferences.getString(_musicButtonShortcutsKey);
      if (rawMusicButtonShortcuts != null) {
        final decoded = jsonDecode(rawMusicButtonShortcuts);
        if (decoded is List) {
          final values = decoded.whereType<String>().toList();
          const legacyDefaults = ['explore', 'music', 'files', 'videos', 'photos', 'documents'];
          if (values.length == legacyDefaults.length && values.toSet().containsAll(legacyDefaults)) {
            _musicButtonShortcuts = List.of(musicButtonShortcutDefaults);
          } else if (values.isNotEmpty && values.length == decoded.length &&
              values.toSet().length == values.length &&
              values.every(musicButtonShortcutDestinations.contains)) {
            _musicButtonShortcuts = values;
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

  Future<void> setMusicButtonShortcuts(List<String> shortcuts) async {
    if (shortcuts.isEmpty ||
        shortcuts.toSet().length != shortcuts.length ||
        !shortcuts.every(musicButtonShortcutDestinations.contains)) {
      throw ArgumentError('Invalid Music button shortcuts');
    }
    _musicButtonShortcuts = List.of(shortcuts);
    notifyListeners();
    final snapshot = List<String>.of(_musicButtonShortcuts);
    final write = _musicButtonShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_musicButtonShortcutsKey, jsonEncode(snapshot));
    });
    _musicButtonShortcutsWrite = write;
    await write;
  }

  Future<void> resetMusicButtonShortcuts() async {
    _musicButtonShortcuts = List.of(musicButtonShortcutDefaults);
    notifyListeners();
    final write = _musicButtonShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(_musicButtonShortcutsKey),
      ]);
    });
    _musicButtonShortcutsWrite = write;
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

  static String _validMusicSwipeAction(String? action, String fallback) =>
      const {'next', 'previous', 'none'}.contains(action) ? action! : fallback;

  Future<void> setMusicButtonOptions({
    bool? swipeEnabled,
    String? swipeLeftAction,
    String? swipeRightAction,
    bool? longPressEnabled,
  }) async {
    if (swipeLeftAction != null &&
        !const {'next', 'previous', 'none'}.contains(swipeLeftAction)) {
      throw ArgumentError.value(swipeLeftAction, 'swipeLeftAction');
    }
    if (swipeRightAction != null &&
        !const {'next', 'previous', 'none'}.contains(swipeRightAction)) {
      throw ArgumentError.value(swipeRightAction, 'swipeRightAction');
    }
    if (swipeEnabled != null) _musicButtonSwipeEnabled = swipeEnabled;
    if (swipeLeftAction != null) _musicButtonSwipeLeftAction = swipeLeftAction;
    if (swipeRightAction != null) _musicButtonSwipeRightAction = swipeRightAction;
    if (longPressEnabled != null) _musicButtonLongPressEnabled = longPressEnabled;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (swipeEnabled != null) preferences.setBool(_musicButtonSwipeEnabledKey, swipeEnabled),
      if (swipeLeftAction != null) preferences.setString(_musicButtonSwipeLeftActionKey, swipeLeftAction),
      if (swipeRightAction != null) preferences.setString(_musicButtonSwipeRightActionKey, swipeRightAction),
      if (longPressEnabled != null) preferences.setBool(_musicButtonLongPressEnabledKey, longPressEnabled),
    ]);
  }

  Future<void> resetMusicButtonOptions() async {
    _musicButtonSwipeEnabled = true;
    _musicButtonSwipeLeftAction = 'next';
    _musicButtonSwipeRightAction = 'previous';
    _musicButtonLongPressEnabled = true;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_musicButtonSwipeEnabledKey),
      preferences.remove(_musicButtonSwipeLeftActionKey),
      preferences.remove(_musicButtonSwipeRightActionKey),
      preferences.remove(_musicButtonLongPressEnabledKey),
    ]);
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

  Future<void> setVideoPlayerOptions({
    int? controlsTimeoutSeconds, int? seekSeconds, double? defaultSpeed,
    String? fitMode, bool? gesturesEnabled, bool? pinchZoomEnabled, bool? tapToTogglePlayback,
    double? subtitleFontSize, bool? subtitleBackground, bool? autoFullscreen,
    String? fullscreenOrientation,
  }) async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0];
    if (controlsTimeoutSeconds != null && ![0, 3, 4, 5, 8, 12].contains(controlsTimeoutSeconds)) throw ArgumentError.value(controlsTimeoutSeconds, 'controlsTimeoutSeconds');
    if (seekSeconds != null && ![5, 10, 15, 30].contains(seekSeconds)) throw ArgumentError.value(seekSeconds, 'seekSeconds');
    if (defaultSpeed != null && !speeds.contains(defaultSpeed)) throw ArgumentError.value(defaultSpeed, 'defaultSpeed');
    if (fitMode != null && !['contain', 'cover', 'fill'].contains(fitMode)) throw ArgumentError.value(fitMode, 'fitMode');
    if (subtitleFontSize != null && (subtitleFontSize < 14 || subtitleFontSize > 32)) throw ArgumentError.value(subtitleFontSize, 'subtitleFontSize');
    if (fullscreenOrientation != null && !['landscape', 'portrait', 'auto'].contains(fullscreenOrientation)) throw ArgumentError.value(fullscreenOrientation, 'fullscreenOrientation');
    if (controlsTimeoutSeconds != null) _videoControlsTimeoutSeconds = controlsTimeoutSeconds;
    if (seekSeconds != null) _videoSeekSeconds = seekSeconds;
    if (defaultSpeed != null) _videoDefaultSpeed = defaultSpeed;
    if (fitMode != null) _videoFitMode = fitMode;
    if (gesturesEnabled != null) _videoGesturesEnabled = gesturesEnabled;
    if (pinchZoomEnabled != null) _videoPinchZoomEnabled = pinchZoomEnabled;
    if (tapToTogglePlayback != null) _videoTapToTogglePlayback = tapToTogglePlayback;
    if (subtitleFontSize != null) _videoSubtitleFontSize = subtitleFontSize;
    if (subtitleBackground != null) _videoSubtitleBackground = subtitleBackground;
    if (autoFullscreen != null) _videoAutoFullscreen = autoFullscreen;
    if (fullscreenOrientation != null) _videoFullscreenOrientation = fullscreenOrientation;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (controlsTimeoutSeconds != null) preferences.setInt(_videoControlsTimeoutKey, controlsTimeoutSeconds),
      if (seekSeconds != null) preferences.setInt(_videoSeekSecondsKey, seekSeconds),
      if (defaultSpeed != null) preferences.setDouble(_videoDefaultSpeedKey, defaultSpeed),
      if (fitMode != null) preferences.setString(_videoFitModeKey, fitMode),
      if (gesturesEnabled != null) preferences.setBool(_videoGesturesKey, gesturesEnabled),
      if (pinchZoomEnabled != null) preferences.setBool(_videoPinchZoomKey, pinchZoomEnabled),
      if (tapToTogglePlayback != null) preferences.setBool(_videoTapToggleKey, tapToTogglePlayback),
      if (subtitleFontSize != null) preferences.setDouble(_videoSubtitleFontSizeKey, subtitleFontSize),
      if (subtitleBackground != null) preferences.setBool(_videoSubtitleBackgroundKey, subtitleBackground),
      if (autoFullscreen != null) preferences.setBool(_videoAutoFullscreenKey, autoFullscreen),
      if (fullscreenOrientation != null) preferences.setString(_videoFullscreenOrientationKey, fullscreenOrientation),
    ]);
  }

  Future<void> resetVideoPlayerOptions() async {
    _videoControlsTimeoutSeconds = 4;
    _videoSeekSeconds = 10;
    _videoDefaultSpeed = 1.0;
    _videoFitMode = 'contain';
    _videoGesturesEnabled = true;
    _videoPinchZoomEnabled = true;
    _videoTapToTogglePlayback = false;
    _videoSubtitleFontSize = 20;
    _videoSubtitleBackground = true;
    _videoAutoFullscreen = false;
    _videoFullscreenOrientation = 'landscape';
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_videoControlsTimeoutKey), preferences.remove(_videoSeekSecondsKey),
      preferences.remove(_videoDefaultSpeedKey), preferences.remove(_videoFitModeKey),
      preferences.remove(_videoGesturesKey), preferences.remove(_videoPinchZoomKey), preferences.remove(_videoTapToggleKey),
      preferences.remove(_videoSubtitleFontSizeKey), preferences.remove(_videoSubtitleBackgroundKey),
      preferences.remove(_videoAutoFullscreenKey), preferences.remove(_videoFullscreenOrientationKey),
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
