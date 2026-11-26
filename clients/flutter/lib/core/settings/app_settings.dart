import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_migrations.dart';

part 'app_settings_appearance.dart';
part 'app_settings_media.dart';
part 'app_settings_navigation.dart';

List<String>? _decodeStoredStringList(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((value) => value is! String)) {
      return null;
    }
    return List<String>.from(decoded);
  } on FormatException {
    return null;
  }
}

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  void _notifySettingsChanged() => notifyListeners();

  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'settings_theme_mode';
  static const _downloadKey = 'settings_download_directory';
  static const _quickActionsKey = 'settings_home_quick_actions';
  static const _libraryKey = 'settings_home_library';
  static const _recentKey = 'settings_home_recent';
  static const _liquidGlassKey = 'settings_use_liquid_glass';
  static const _progressiveBlurKey = 'settings_progressive_blur_enabled';
  static const _navigationOrderKey = 'settings_navigation_order';
  static const _navigationVisibilityKey = 'settings_navigation_visibility';
  static const _homeSearchKey = 'settings_home_search';
  static const _homeTransfersKey = 'settings_home_transfers';
  static const _homeSectionOrderKey = 'settings_home_section_order';
  static const _musicButtonShortcutsKey = AppSettingsMigrations.musicButtonShortcutsKey;
  static const _legacyFloatingShortcutsKey = AppSettingsMigrations.legacyFloatingShortcutsKey;
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
  static const _discoverEnabledKey = 'settings_discover_enabled';
  static const _showDiscoverOnWelcomeKey = 'settings_show_discover_on_welcome';
  static const _discoverLocalLosslessKey = 'settings_discover_local_lossless';
  static const _discoverLyricsKey = 'settings_discover_lyrics';
  static const _discoverAutoQueueKey = 'settings_discover_auto_queue';
  static const _discoverArtworkKey = 'settings_discover_artwork';
  static const _discoverAudioQualityKey = 'settings_discover_audio_quality';
  static const _discoverResolverProfileKey = 'settings_discover_resolver_profile';
  static const _discoverRegionKey = 'settings_discover_region';
  static const discoverRegions = <String, String>{
    'IN': 'India',
    'US': 'United States',
    'GB': 'United Kingdom',
    'CA': 'Canada',
    'AU': 'Australia',
    'JP': 'Japan',
    'KR': 'South Korea',
    'DE': 'Germany',
    'FR': 'France',
    'BR': 'Brazil',
    'MX': 'Mexico',
    'ID': 'Indonesia',
    'PH': 'Philippines',
    'SG': 'Singapore',
    'MY': 'Malaysia',
    'TH': 'Thailand',
    'AE': 'United Arab Emirates',
    'SA': 'Saudi Arabia',
    'ZA': 'South Africa',
    'NG': 'Nigeria',
  };
  static const homeSectionDefaults = <String>['search', 'quick', 'transfers', 'continue', 'recent'];
  static const navigationDefaults = <String>['home', 'explore', 'files', 'browse'];
  static const musicButtonShortcutDefaults =
      AppSettingsMigrations.musicButtonShortcutDefaults;
  static const musicButtonShortcutDestinations =
      AppSettingsMigrations.musicButtonShortcutDestinations;

  ThemeMode _themeMode = ThemeMode.system;
  bool _amoled = false;
  String? _downloadDirectory;
  bool _showQuickActions = true;
  bool _showLibrary = true;
  bool _showRecentFiles = true;
  bool _showGlobalSearch = true;
  bool _showActiveTransfers = true;
  List<String> _homeSectionOrder = List.of(homeSectionDefaults);
  bool _useLiquidGlass = true;
  bool _progressiveBlurEnabled = true;
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
  bool _discoverEnabled = true;
  bool _showDiscoverOnWelcome = true;
  bool _discoverLocalLossless = true;
  bool _discoverLyrics = true;
  bool _discoverAutoQueue = true;
  bool _discoverArtwork = true;
  String _discoverAudioQuality = 'best_available';
  String _discoverResolverProfile = 'automatic';
  String _discoverRegion = 'IN';

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
  bool get discoverEnabled => _discoverEnabled;
  bool get showDiscoverOnWelcome => _showDiscoverOnWelcome;
  bool get discoverLocalLossless => _discoverLocalLossless;
  bool get discoverLyrics => _discoverLyrics;
  bool get discoverAutoQueue => _discoverAutoQueue;
  bool get discoverArtwork => _discoverArtwork;
  String get discoverAudioQuality => _discoverAudioQuality;
  String get discoverResolverProfile => _discoverResolverProfile;
  String get discoverRegion => _discoverRegion;

  Future<void> reloadPreferences() async {
    _loaded = false;
    await load();
  }

  Future<void> load() async {
    if (_loaded) return;
    _homeSectionOrder = List.of(homeSectionDefaults);
    _navigationOrder = List.of(navigationDefaults);
    _visibleNavigationItems = Set.of(navigationDefaults);
    try {
      final preferences = await SharedPreferences.getInstance();
      _useLiquidGlass = preferences.getBool(_liquidGlassKey) ?? true;
      _progressiveBlurEnabled = preferences.getBool(_progressiveBlurKey) ?? true;
      _showMiniPlayer = preferences.getBool(_nowPlayingMiniPlayerKey) ?? true;
      _enableNowPlayingGestures = preferences.getBool(_nowPlayingGesturesKey) ?? true;
      _showStatsForNerds = preferences.getBool(_nowPlayingStatsForNerdsKey) ?? true;
      _nowPlayingTheme = const {'apple', 'blur', 'blurCard', 'gradient', 'aether'}
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
      _discoverEnabled = preferences.getBool(_discoverEnabledKey) ?? true;
      _showDiscoverOnWelcome = preferences.getBool(_showDiscoverOnWelcomeKey) ?? true;
      _discoverLocalLossless = preferences.getBool(_discoverLocalLosslessKey) ?? true;
      _discoverLyrics = preferences.getBool(_discoverLyricsKey) ?? true;
      _discoverAutoQueue = preferences.getBool(_discoverAutoQueueKey) ?? true;
      _discoverArtwork = preferences.getBool(_discoverArtworkKey) ?? true;
      _discoverAudioQuality = const {'best_available', 'balanced', 'data_saver'}
          .contains(preferences.getString(_discoverAudioQualityKey))
          ? preferences.getString(_discoverAudioQualityKey)!
          : 'best_available';
      _discoverResolverProfile = const {'automatic', 'newpipe_first', 'player_api_first'}
          .contains(preferences.getString(_discoverResolverProfileKey))
          ? preferences.getString(_discoverResolverProfileKey)!
          : 'automatic';
      final storedRegion = preferences.getString(_discoverRegionKey);
      _discoverRegion = discoverRegions.containsKey(storedRegion) ? storedRegion! : 'IN';
      _musicButtonSwipeEnabled = preferences.getBool(_musicButtonSwipeEnabledKey) ?? true;
      _musicButtonSwipeLeftAction = _validMusicSwipeAction(preferences.getString(_musicButtonSwipeLeftActionKey), 'next');
      _musicButtonSwipeRightAction = _validMusicSwipeAction(preferences.getString(_musicButtonSwipeRightActionKey), 'previous');
      _musicButtonLongPressEnabled = preferences.getBool(_musicButtonLongPressEnabledKey) ?? true;
      _musicButtonShortcuts =
          await AppSettingsMigrations.migrateMusicButtonShortcuts(preferences);
      _showGlobalSearch = preferences.getBool(_homeSearchKey) ?? true;
      _showActiveTransfers = preferences.getBool(_homeTransfersKey) ?? true;
      final sectionValues = _decodeStoredStringList(
        preferences.getString(_homeSectionOrderKey),
      );
      if (sectionValues != null &&
          sectionValues.length == homeSectionDefaults.length &&
          sectionValues.toSet().length == homeSectionDefaults.length &&
          sectionValues.toSet().containsAll(homeSectionDefaults)) {
        _homeSectionOrder = sectionValues;
      }

      final navigationValues = _decodeStoredStringList(
        preferences.getString(_navigationOrderKey),
      );
      if (navigationValues != null &&
          navigationValues.length == navigationDefaults.length &&
          navigationValues.toSet().length == navigationDefaults.length &&
          navigationValues.toSet().containsAll(navigationDefaults)) {
        _navigationOrder = navigationValues;
      }

      final visibilityValues = _decodeStoredStringList(
        preferences.getString(_navigationVisibilityKey),
      );
      if (visibilityValues != null) {
        final values = visibilityValues.toSet();
        if (values.contains('home') &&
            values.length >= 2 &&
            values.every(navigationDefaults.contains)) {
          _visibleNavigationItems = values;
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
