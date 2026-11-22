import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings_migrations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('upgrades the previous Music shortcut defaults with Drives', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppSettingsMigrations.musicButtonShortcutsKey,
      '["photos","music","videos","documents","files","search"]',
    );

    final shortcuts =
        await AppSettingsMigrations.migrateMusicButtonShortcuts(preferences);

    expect(shortcuts, AppSettingsMigrations.musicButtonShortcutDefaults);
    expect(
      preferences.getString(AppSettingsMigrations.musicButtonShortcutsKey),
      '["photos","music","videos","documents","files","search","drives"]',
    );
  });

  test('migrates legacy floating shortcuts and removes obsolete keys', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppSettingsMigrations.legacyFloatingShortcutsKey,
      '["explore","music","files","videos","photos","documents"]',
    );
    await preferences.setBool('settings_floating_shortcut_enabled', true);
    await preferences.setString('settings_floating_shortcut_tap_action', 'music');
    await preferences.setBool('settings_floating_shortcut_long_press', true);

    final shortcuts =
        await AppSettingsMigrations.migrateMusicButtonShortcuts(preferences);

    expect(shortcuts, AppSettingsMigrations.musicButtonShortcutDefaults);
    expect(
      preferences.getString(AppSettingsMigrations.musicButtonShortcutsKey),
      '["photos","music","videos","documents","files","search","drives"]',
    );
    expect(
      preferences.containsKey(AppSettingsMigrations.legacyFloatingShortcutsKey),
      isFalse,
    );
    expect(preferences.containsKey('settings_floating_shortcut_enabled'), isFalse);
    expect(preferences.containsKey('settings_floating_shortcut_tap_action'), isFalse);
    expect(preferences.containsKey('settings_floating_shortcut_long_press'), isFalse);
  });

  test('preserves a valid custom shortcut order', () async {
    final preferences = await SharedPreferences.getInstance();
    const custom = ['music', 'files', 'photos', 'upload', 'drives'];
    await preferences.setString(
      AppSettingsMigrations.musicButtonShortcutsKey,
      '["music","files","photos","upload","drives"]',
    );

    final shortcuts =
        await AppSettingsMigrations.migrateMusicButtonShortcuts(preferences);

    expect(shortcuts, custom);
    expect(
      preferences.getString(AppSettingsMigrations.musicButtonShortcutsKey),
      '["music","files","photos","upload","drives"]',
    );
  });

  test('uses defaults when stored shortcut list is empty or duplicated', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppSettingsMigrations.musicButtonShortcutsKey,
      '["music","music"]',
    );

    final shortcuts =
        await AppSettingsMigrations.migrateMusicButtonShortcuts(preferences);

    expect(shortcuts, AppSettingsMigrations.musicButtonShortcutDefaults);
  });
}
