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

  Future<void> setAnimationsEnabled(bool value) async {
    if (_animationsEnabled == value) return;
    _animationsEnabled = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._animationsEnabledKey, value);
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

  Future<void> setProgressiveBlurEnabled(bool value) async {
    _progressiveBlurEnabled = value;
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(AppSettings._progressiveBlurKey, value);
  }

}
