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

}
