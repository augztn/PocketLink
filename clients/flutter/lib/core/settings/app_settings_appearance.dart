part of 'app_settings.dart';

extension AppSettingsAppearance on AppSettings {
  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    _amoled = false;
    _notifySettingsChanged();
    await AppSettings._storage.write(key: AppSettings._themeKey, value: switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setAmoled(bool value) async {
    _amoled = value;
    if (value) _themeMode = ThemeMode.dark;
    _notifySettingsChanged();
    await AppSettings._storage.write(key: AppSettings._themeKey, value: value ? 'amoled' : 'dark');
  }

  Future<void> setUseLiquidGlass(bool value) async {
    _useLiquidGlass = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._liquidGlassKey, value);
  }

  Future<void> setNowPlayingPlayerStyle(String value) async {
    if (!const {'pocketlink', 'poster', 'lyrics'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported Now Playing style');
    }
    if (_nowPlayingPlayerStyle == value) return;
    _nowPlayingPlayerStyle = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(AppSettings._nowPlayingPlayerStyleKey, value);
  }

  Future<void> setAnimationsEnabled(bool value) async {
    if (_animationsEnabled == value) return;
    _animationsEnabled = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._animationsEnabledKey, value);
  }

  Future<void> setPageTransitionsEnabled(bool value) async {
    if (_pageTransitionsEnabled == value) return;
    _pageTransitionsEnabled = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._pageTransitionsEnabledKey, value);
  }

  Future<void> setLyricsAnimationsEnabled(bool value) async {
    if (_lyricsAnimationsEnabled == value) return;
    _lyricsAnimationsEnabled = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._lyricsAnimationsEnabledKey, value);
  }

  Future<void> setAnimationSpeed(double value) async {
    if (!value.isFinite || value < 0.5 || value > 2.0) {
      throw ArgumentError.value(value, 'value', 'Must be between 0.5x and 2.0x');
    }
    if ((_animationSpeed - value).abs() < 0.001) return;
    _animationSpeed = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(AppSettings._animationSpeedKey, value);
  }

  Future<void> setAccentColor(int value) async {
    if (!AppSettings.accentColorValues.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported accent color');
    }
    if (_accentColorValue == value) return;
    _accentColorValue = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(AppSettings._accentColorKey, value);
  }

  Future<void> setBlurStrength(double value) async {
    if (!value.isFinite || value < 0 || value > 32) {
      throw ArgumentError.value(value, 'value', 'Must be between 0 and 32');
    }
    if ((_blurStrength - value).abs() < 0.01) return;
    _blurStrength = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(AppSettings._blurStrengthKey, value);
  }

  Future<void> setGlassBlurStrength(double value) async {
    if (!value.isFinite || value < 0 || value > 32) {
      throw ArgumentError.value(value, 'value', 'Must be between 0 and 32');
    }
    if ((_glassBlurStrength - value).abs() < 0.01) return;
    _glassBlurStrength = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(AppSettings._glassBlurStrengthKey, value);
  }

  Future<void> setThumbnailCornerRadius(double value) async {
    if (!value.isFinite || value < 0 || value > 45) {
      throw ArgumentError.value(value, 'value', 'Must be between 0 and 45');
    }
    if ((_thumbnailCornerRadius - value).abs() < 0.01) return;
    _thumbnailCornerRadius = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(AppSettings._thumbnailCornerRadiusKey, value);
  }

  Future<void> setLyricsOptions({
    double? textSize,
    double? lineSpacing,
    String? motionStyle,
    bool? glow,
    bool? bloom,
    bool? softLight,
    double? inactiveBlur,
  }) async {
    if (textSize != null && (!textSize.isFinite || textSize < 14 || textSize > 44)) {
      throw ArgumentError.value(textSize, 'textSize', 'Must be between 14 and 44');
    }
    if (lineSpacing != null && (!lineSpacing.isFinite || lineSpacing < 0.8 || lineSpacing > 2.0)) {
      throw ArgumentError.value(lineSpacing, 'lineSpacing', 'Must be between 0.8 and 2.0');
    }
    if (motionStyle != null && !const {'motion', 'legacy', 'boring', 'plain'}.contains(motionStyle)) {
      throw ArgumentError.value(motionStyle, 'motionStyle');
    }
    if (inactiveBlur != null && (!inactiveBlur.isFinite || inactiveBlur < 0 || inactiveBlur > 4)) {
      throw ArgumentError.value(inactiveBlur, 'inactiveBlur', 'Must be between 0 and 4');
    }
    if (textSize != null) _lyricsTextSize = textSize;
    if (lineSpacing != null) _lyricsLineSpacing = lineSpacing;
    if (motionStyle != null) _lyricsMotionStyle = motionStyle;
    if (glow != null) _lyricsGlow = glow;
    if (bloom != null) _lyricsBloom = bloom;
    if (softLight != null) _lyricsSoftLight = softLight;
    if (inactiveBlur != null) _lyricsInactiveBlur = inactiveBlur;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (textSize != null) preferences.setDouble(AppSettings._lyricsTextSizeKey, textSize),
      if (lineSpacing != null) preferences.setDouble(AppSettings._lyricsLineSpacingKey, lineSpacing),
      if (motionStyle != null) preferences.setString(AppSettings._lyricsMotionStyleKey, motionStyle),
      if (glow != null) preferences.setBool(AppSettings._lyricsGlowKey, glow),
      if (bloom != null) preferences.setBool(AppSettings._lyricsBloomKey, bloom),
      if (softLight != null) preferences.setBool(AppSettings._lyricsSoftLightKey, softLight),
      if (inactiveBlur != null) preferences.setDouble(AppSettings._lyricsInactiveBlurKey, inactiveBlur),
    ]);
  }

  Future<void> setCustomFont({
    required String path,
    required String family,
    required String name,
  }) async {
    if (path.trim().isEmpty || family.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Font path, family and display name are required.');
    }
    await AppSettings._loadCustomFontFile(path, family);
    final previousPath = _customFontPath;
    _customFontPath = path;
    _customFontFamily = family;
    _customFontName = name;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(AppSettings._customFontPathKey, path),
      preferences.setString(AppSettings._customFontFamilyKey, family),
      preferences.setString(AppSettings._customFontNameKey, name),
    ]);
    if (previousPath != null && previousPath != path) {
      try {
        await File(previousPath).delete();
      } on FileSystemException {
        // Replacing a font should not fail because an old file is unavailable.
      }
    }
  }

  Future<void> clearCustomFont() async {
    final oldPath = _customFontPath;
    _customFontPath = null;
    _customFontFamily = null;
    _customFontName = null;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(AppSettings._customFontPathKey),
      preferences.remove(AppSettings._customFontFamilyKey),
      preferences.remove(AppSettings._customFontNameKey),
    ]);
    if (oldPath != null) {
      try {
        await File(oldPath).delete();
      } on FileSystemException {
        // A missing or inaccessible old font must not block restoring defaults.
      }
    }
  }

  Future<void> setProgressiveBlurEnabled(bool value) async {
    _progressiveBlurEnabled = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._progressiveBlurKey, value);
  }

}
