part of 'app_settings.dart';

extension AppSettingsMedia on AppSettings {
  Future<void> setDiscoverMotionSpeed(String value) async {
    if (!const {'fast', 'normal', 'slow'}.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    if (_discoverMotionSpeed == value) return;
    _discoverMotionSpeed = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(AppSettings._discoverMotionSpeedKey, value);
  }

  Future<void> setDiscoverMotion(bool value) async {
    if (_discoverMotion == value) return;
    _discoverMotion = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._discoverMotionKey, value);
  }

  Future<void> setShowDiscoverOnWelcome(bool value) async {
    if (_showDiscoverOnWelcome == value) return;
    _showDiscoverOnWelcome = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._showDiscoverOnWelcomeKey, value);
  }

  Future<void> setDiscoverOptions({
    bool? enabled,
    bool? localLossless,
    bool? lyrics,
    bool? autoQueue,
    bool? artwork,
    bool? spotlight,
    bool? artistGrid,
  }) async {
    if (enabled != null) _discoverEnabled = enabled;
    if (localLossless != null) _discoverLocalLossless = localLossless;
    if (lyrics != null) _discoverLyrics = lyrics;
    if (autoQueue != null) _discoverAutoQueue = autoQueue;
    if (artwork != null) _discoverArtwork = artwork;
    if (spotlight != null) _discoverSpotlight = spotlight;
    if (artistGrid != null) _discoverArtistGrid = artistGrid;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (enabled != null) preferences.setBool(AppSettings._discoverEnabledKey, enabled),
      if (localLossless != null) preferences.setBool(AppSettings._discoverLocalLosslessKey, localLossless),
      if (lyrics != null) preferences.setBool(AppSettings._discoverLyricsKey, lyrics),
      if (autoQueue != null) preferences.setBool(AppSettings._discoverAutoQueueKey, autoQueue),
      if (artwork != null) preferences.setBool(AppSettings._discoverArtworkKey, artwork),
      if (spotlight != null) preferences.setBool(AppSettings._discoverSpotlightKey, spotlight),
      if (artistGrid != null) preferences.setBool(AppSettings._discoverArtistGridKey, artistGrid),
    ]);
  }

  Future<void> setDiscoverPlaybackOptions({
    String? audioQuality,
    String? resolverProfile,
    String? region,
  }) async {
    if (audioQuality != null &&
        !const {'best_available', 'balanced', 'data_saver'}.contains(audioQuality)) {
      throw ArgumentError.value(audioQuality, 'audioQuality');
    }
    if (resolverProfile != null &&
        !const {'automatic', 'newpipe_first', 'player_api_first'}.contains(resolverProfile)) {
      throw ArgumentError.value(resolverProfile, 'resolverProfile');
    }
    if (region != null && !AppSettings.discoverRegions.containsKey(region)) {
      throw ArgumentError.value(region, 'region');
    }
    if (audioQuality != null) _discoverAudioQuality = audioQuality;
    if (resolverProfile != null) _discoverResolverProfile = resolverProfile;
    if (region != null) _discoverRegion = region;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (audioQuality != null) preferences.setString(AppSettings._discoverAudioQualityKey, audioQuality),
      if (resolverProfile != null) preferences.setString(AppSettings._discoverResolverProfileKey, resolverProfile),
      if (region != null) preferences.setString(AppSettings._discoverRegionKey, region),
    ]);
  }

  Future<void> setDownloadDirectory(String? value) async {
    _downloadDirectory = value;
    _notifySettingsChanged();
    if (value == null) {
      await AppSettings._storage.delete(key: AppSettings._downloadKey);
    } else {
      await AppSettings._storage.write(key: AppSettings._downloadKey, value: value);
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
      if (swipeEnabled != null) preferences.setBool(AppSettings._musicButtonSwipeEnabledKey, swipeEnabled),
      if (swipeLeftAction != null) preferences.setString(AppSettings._musicButtonSwipeLeftActionKey, swipeLeftAction),
      if (swipeRightAction != null) preferences.setString(AppSettings._musicButtonSwipeRightActionKey, swipeRightAction),
      if (longPressEnabled != null) preferences.setBool(AppSettings._musicButtonLongPressEnabledKey, longPressEnabled),
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
      preferences.remove(AppSettings._musicButtonSwipeEnabledKey),
      preferences.remove(AppSettings._musicButtonSwipeLeftActionKey),
      preferences.remove(AppSettings._musicButtonSwipeRightActionKey),
      preferences.remove(AppSettings._musicButtonLongPressEnabledKey),
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
      if (miniPlayer != null) preferences.setBool(AppSettings._nowPlayingMiniPlayerKey, miniPlayer),
      if (gestures != null) preferences.setBool(AppSettings._nowPlayingGesturesKey, gestures),
      if (statsForNerds != null) preferences.setBool(AppSettings._nowPlayingStatsForNerdsKey, statsForNerds),
    ]);
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
      if (concurrency != null) preferences.setInt(AppSettings._downloadConcurrencyKey, concurrency),
      if (wifiOnly != null) preferences.setBool(AppSettings._downloadWifiOnlyKey, wifiOnly),
      if (autoResume != null) preferences.setBool(AppSettings._downloadAutoResumeKey, autoResume),
    ]);
  }

  Future<void> resetNowPlayingOptions() async {
    _showMiniPlayer = true;
    _enableNowPlayingGestures = true;
    _showStatsForNerds = true;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(AppSettings._nowPlayingMiniPlayerKey),
      preferences.remove(AppSettings._nowPlayingGesturesKey),
      preferences.remove(AppSettings._nowPlayingStatsForNerdsKey),
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
      if (controlsTimeoutSeconds != null) preferences.setDouble(AppSettings._videoControlsTimeoutKey, controlsTimeoutSeconds),
      if (seekSeconds != null) preferences.setInt(AppSettings._videoSeekSecondsKey, seekSeconds),
      if (defaultSpeed != null) preferences.setDouble(AppSettings._videoDefaultSpeedKey, defaultSpeed),
      if (fitMode != null) preferences.setString(AppSettings._videoFitModeKey, fitMode),
      if (gesturesEnabled != null) preferences.setBool(AppSettings._videoGesturesKey, gesturesEnabled),
      if (pinchZoomEnabled != null) preferences.setBool(AppSettings._videoPinchZoomKey, pinchZoomEnabled),
      if (tapToTogglePlayback != null) preferences.setBool(AppSettings._videoTapToggleKey, tapToTogglePlayback),
      if (subtitleFontSize != null) preferences.setDouble(AppSettings._videoSubtitleFontSizeKey, subtitleFontSize),
      if (subtitleBackground != null) preferences.setBool(AppSettings._videoSubtitleBackgroundKey, subtitleBackground),
      if (autoFullscreen != null) preferences.setBool(AppSettings._videoAutoFullscreenKey, autoFullscreen),
      if (fullscreenOrientation != null) preferences.setString(AppSettings._videoFullscreenOrientationKey, fullscreenOrientation),
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
      preferences.remove(AppSettings._videoControlsTimeoutKey), preferences.remove(AppSettings._videoSeekSecondsKey),
      preferences.remove(AppSettings._videoDefaultSpeedKey), preferences.remove(AppSettings._videoFitModeKey),
      preferences.remove(AppSettings._videoGesturesKey), preferences.remove(AppSettings._videoPinchZoomKey), preferences.remove(AppSettings._videoTapToggleKey),
      preferences.remove(AppSettings._videoSubtitleFontSizeKey), preferences.remove(AppSettings._videoSubtitleBackgroundKey),
      preferences.remove(AppSettings._videoAutoFullscreenKey), preferences.remove(AppSettings._videoFullscreenOrientationKey),
    ]);
  }


}
