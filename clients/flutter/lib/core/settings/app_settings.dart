import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_settings_appearance.dart';
part 'app_settings_media.dart';
part 'app_settings_navigation.dart';

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
  static const _progressiveBlurKey = 'settings_progressive_blur';
  static const _progressiveBlurStrengthKey = 'settings_progressive_blur_strength';
  static const _navigationOrderKey = 'settings_navigation_order';
  static const _navigationVisibilityKey = 'settings_navigation_visibility';
  static const _homeSearchKey = 'settings_home_search';
  static const _homeTransfersKey = 'settings_home_transfers';
  static const _homeSectionOrderKey = 'settings_home_section_order';
  static const _musicButtonShortcutsKey = 'settings_music_button_shortcuts';
  static const _legacyFloatingShortcutsKey = 'settings_floating_shortcuts';
  static const _musicButtonSwipeEnabledKey = 'settings_music_button_swipe_enabled';
  static const _musicButtonSwipeLeftActionKey = 'settings_music_button_swipe_left_action';
  static const _musicButtonSwipeRightActionKey = 'settings_music_button_swipe_right_action';
  static const _musicButtonLongPressEnabledKey = 'settings_music_button_long_press_enabled';
  static const _nowPlayingMiniPlayerKey = 'settings_now_playing_mini_player';
  static const _nowPlayingGesturesKey = 'settings_now_playing_gestures';
  static const _nowPlayingStatsForNerdsKey = 'settings_now_playing_stats_for_nerds';
  static const _nowPlayingScrubberStyleKey = 'settings_now_playing_scrubber_style';
  static const _nowPlayingThemeKey = 'settings_now_playing_theme';
  static const _downloadConcurrencyKey = 'settings_download_concurrency';
  static const _downloadWifiOnlyKey = 'settings_download_wifi_only';
  static const _downloadAutoResumeKey = 'settings_download_auto_resume';
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
  bool _progressiveBlurEnabled = false;
  double _progressiveBlurStrength = 55;
  Future<void> _progressiveBlurWrite = Future<void>.value();
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
  String _nowPlayingScrubberStyle = 'apple';
  String _nowPlayingTheme = 'apple';
  int _downloadConcurrency = 2;
  bool _downloadWifiOnly = false;
  bool _downloadAutoResume = true;
  double _videoControlsTimeoutSeconds = 3.5;
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
  bool get progressiveBlurEnabled => _progressiveBlurEnabled;
  double get progressiveBlurStrength => _progressiveBlurStrength;
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
  String get nowPlayingScrubberStyle => _nowPlayingScrubberStyle;
  String get nowPlayingTheme => _nowPlayingTheme;
  int get downloadConcurrency => _downloadConcurrency;
  bool get downloadWifiOnly => _downloadWifiOnly;
  bool get downloadAutoResume => _downloadAutoResume;
  double get videoControlsTimeoutSeconds => _videoControlsTimeoutSeconds;
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

  void _notifySettingsChanged() => notifyListeners();

  Future<void> reloadPreferences() async {
    _loaded = false;
    await load();
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _useLiquidGlass = preferences.getBool(_liquidGlassKey) ?? false;
      _progressiveBlurEnabled = preferences.getBool(_progressiveBlurKey) ?? false;
      final storedBlurStrength = preferences.get(_progressiveBlurStrengthKey);
      _progressiveBlurStrength = storedBlurStrength is num
          ? storedBlurStrength.toDouble().clamp(0, 100).toDouble()
          : 55;
      _showMiniPlayer = preferences.getBool(_nowPlayingMiniPlayerKey) ?? true;
      _enableNowPlayingGestures = preferences.getBool(_nowPlayingGesturesKey) ?? true;
      _showStatsForNerds = preferences.getBool(_nowPlayingStatsForNerdsKey) ?? true;
      _nowPlayingTheme = const {'apple', 'blur', 'blurCard', 'gradient'}
          .contains(preferences.getString(_nowPlayingThemeKey))
          ? preferences.getString(_nowPlayingThemeKey)!
          : 'apple';
      _downloadConcurrency = const {1, 2, 3, 5}.contains(preferences.getInt(_downloadConcurrencyKey))
          ? preferences.getInt(_downloadConcurrencyKey)!
          : 2;
      _downloadWifiOnly = preferences.getBool(_downloadWifiOnlyKey) ?? false;
      _downloadAutoResume = preferences.getBool(_downloadAutoResumeKey) ?? true;
      _nowPlayingScrubberStyle = const {'apple', 'wavy', 'classic', 'waveform'}
          .contains(preferences.getString(_nowPlayingScrubberStyleKey))
          ? preferences.getString(_nowPlayingScrubberStyleKey)!
          : 'apple';
      final controlsTimeout = preferences.get(_videoControlsTimeoutKey);
      _videoControlsTimeoutSeconds = controlsTimeout is num ? controlsTimeout.toDouble() : 3.5;
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
      final rawMusicButtonShortcuts = preferences.getString(_musicButtonShortcutsKey) ??
          preferences.getString(_legacyFloatingShortcutsKey);
      if (rawMusicButtonShortcuts != null) {
        final decoded = jsonDecode(rawMusicButtonShortcuts);
        if (decoded is List) {
          final values = decoded.whereType<String>()
              .where(musicButtonShortcutDestinations.contains)
              .toList();
          const legacyDefaults = ['explore', 'music', 'files', 'videos', 'photos', 'documents'];
          const previousMusicDefaults = [
            'photos', 'music', 'videos', 'documents', 'files', 'search',
          ];
          final isLegacyDefault = values.length == legacyDefaults.length &&
              values.toSet().containsAll(legacyDefaults);
          final isPreviousDefault = values.length == previousMusicDefaults.length &&
              values.join(',') == previousMusicDefaults.join(',');
          if (isLegacyDefault || isPreviousDefault) {
            _musicButtonShortcuts = List.of(musicButtonShortcutDefaults);
            if (isPreviousDefault && preferences.containsKey(_musicButtonShortcutsKey)) {
              await preferences.setString(
                _musicButtonShortcutsKey,
                jsonEncode(_musicButtonShortcuts),
              );
            }
          } else if (values.isNotEmpty && values.toSet().length == values.length) {
            _musicButtonShortcuts = values;
          }
        }
      }
      if (preferences.containsKey(_legacyFloatingShortcutsKey)) {
        await Future.wait([
          preferences.setString(
            _musicButtonShortcutsKey,
            jsonEncode(_musicButtonShortcuts),
          ),
          preferences.remove(_legacyFloatingShortcutsKey),
        ]);
      }
      await Future.wait([
        preferences.remove('settings_floating_shortcut_enabled'),
        preferences.remove('settings_floating_shortcut_tap_action'),
        preferences.remove('settings_floating_shortcut_long_press'),
      ]);
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

  static String _validMusicSwipeAction(String? action, String fallback) =>
      const {'next', 'previous', 'none'}.contains(action) ? action! : fallback;


}
