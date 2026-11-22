part of 'app_settings.dart';

extension AppSettingsMedia on AppSettings {
  Future<void> setDownloadDirectory(String? value) async {
    _downloadDirectory = value;
    _notifySettingsChanged();
    if (value == null) {
      await _storage.delete(key: _downloadKey);
    } else {
      await _storage.write(key: _downloadKey, value: value);
    }
  }

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
    _notifySettingsChanged();
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
    _notifySettingsChanged();
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
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (miniPlayer != null) preferences.setBool(_nowPlayingMiniPlayerKey, miniPlayer),
      if (gestures != null) preferences.setBool(_nowPlayingGesturesKey, gestures),
      if (statsForNerds != null) preferences.setBool(_nowPlayingStatsForNerdsKey, statsForNerds),
    ]);
  }

  Future<void> setNowPlayingScrubberStyle(String style) async {
    if (!const {'apple', 'wavy', 'classic', 'waveform'}.contains(style)) {
      throw ArgumentError.value(style, 'style');
    }
    if (_nowPlayingScrubberStyle == style) return;
    _nowPlayingScrubberStyle = style;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nowPlayingScrubberStyleKey, style);
  }

  Future<void> setNowPlayingTheme(String theme) async {
    if (!const {'apple', 'blur', 'blurCard', 'gradient'}.contains(theme)) {
      throw ArgumentError.value(theme, 'theme');
    }
    if (_nowPlayingTheme == theme) return;
    _nowPlayingTheme = theme;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nowPlayingThemeKey, theme);
  }

  Future<void> setDownloadOptions({
    int? concurrency,
    bool? wifiOnly,
    bool? autoResume,
  }) async {
    if (concurrency != null && !const {1, 2, 3, 5}.contains(concurrency)) {
      throw ArgumentError.value(concurrency, 'concurrency');
    }
    if (concurrency != null) _downloadConcurrency = concurrency;
    if (wifiOnly != null) _downloadWifiOnly = wifiOnly;
    if (autoResume != null) _downloadAutoResume = autoResume;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (concurrency != null) preferences.setInt(_downloadConcurrencyKey, concurrency),
      if (wifiOnly != null) preferences.setBool(_downloadWifiOnlyKey, wifiOnly),
      if (autoResume != null) preferences.setBool(_downloadAutoResumeKey, autoResume),
    ]);
  }

  Future<void> resetNowPlayingOptions() async {
    _showMiniPlayer = true;
    _enableNowPlayingGestures = true;
    _showStatsForNerds = true;
    _nowPlayingScrubberStyle = 'apple';
    _nowPlayingTheme = 'apple';
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_nowPlayingMiniPlayerKey),
      preferences.remove(_nowPlayingGesturesKey),
      preferences.remove(_nowPlayingStatsForNerdsKey),
      preferences.remove(_nowPlayingScrubberStyleKey),
      preferences.remove(_nowPlayingThemeKey),
    ]);
  }

  Future<void> setVideoPlayerOptions({
    double? controlsTimeoutSeconds, int? seekSeconds, double? defaultSpeed,
    String? fitMode, bool? gesturesEnabled, bool? pinchZoomEnabled, bool? tapToTogglePlayback,
    double? subtitleFontSize, bool? subtitleBackground, bool? autoFullscreen,
    String? fullscreenOrientation,
  }) async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0];
    if (controlsTimeoutSeconds != null && ![0.0, 2.0, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0].contains(controlsTimeoutSeconds)) throw ArgumentError.value(controlsTimeoutSeconds, 'controlsTimeoutSeconds');
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
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (controlsTimeoutSeconds != null) preferences.setDouble(_videoControlsTimeoutKey, controlsTimeoutSeconds),
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
    _videoControlsTimeoutSeconds = 3.5;
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
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_videoControlsTimeoutKey), preferences.remove(_videoSeekSecondsKey),
      preferences.remove(_videoDefaultSpeedKey), preferences.remove(_videoFitModeKey),
      preferences.remove(_videoGesturesKey), preferences.remove(_videoPinchZoomKey), preferences.remove(_videoTapToggleKey),
      preferences.remove(_videoSubtitleFontSizeKey), preferences.remove(_videoSubtitleBackgroundKey),
      preferences.remove(_videoAutoFullscreenKey), preferences.remove(_videoFullscreenOrientationKey),
    ]);
  }


}
