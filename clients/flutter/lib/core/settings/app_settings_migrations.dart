import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Owns legacy preference migrations, keeping compatibility logic out of the
/// observable AppSettings state holder.
class AppSettingsMigrations {
  AppSettingsMigrations._();

  static const musicButtonShortcutsKey = 'settings_music_button_shortcuts';
  static const legacyFloatingShortcutsKey = 'settings_floating_shortcuts';

  static const musicButtonShortcutDefaults = <String>[
    'photos', 'music', 'videos', 'documents', 'files', 'search', 'drives',
  ];

  static const musicButtonShortcutDestinations = <String>{
    'explore', 'files', 'music', 'videos', 'photos', 'documents',
    'favorites', 'upload', 'search', 'drives',
  };

  static Future<List<String>> migrateMusicButtonShortcuts(
    SharedPreferences preferences,
  ) async {
    var shortcuts = List<String>.of(musicButtonShortcutDefaults);
    final rawShortcuts = preferences.getString(musicButtonShortcutsKey) ??
        preferences.getString(legacyFloatingShortcutsKey);

    if (rawShortcuts != null) {
      final decoded = jsonDecode(rawShortcuts);
      if (decoded is List) {
        final values = decoded
            .whereType<String>()
            .where(musicButtonShortcutDestinations.contains)
            .toList();
        const legacyDefaults = [
          'explore', 'music', 'files', 'videos', 'photos', 'documents',
        ];
        const previousMusicDefaults = [
          'photos', 'music', 'videos', 'documents', 'files', 'search',
        ];
        final isLegacyDefault = values.length == legacyDefaults.length &&
            values.toSet().containsAll(legacyDefaults);
        final isPreviousDefault =
            values.length == previousMusicDefaults.length &&
                values.join(',') == previousMusicDefaults.join(',');

        if (isLegacyDefault || isPreviousDefault) {
          shortcuts = List.of(musicButtonShortcutDefaults);
          if (isPreviousDefault &&
              preferences.containsKey(musicButtonShortcutsKey)) {
            await preferences.setString(
              musicButtonShortcutsKey,
              jsonEncode(shortcuts),
            );
          }
        } else if (values.isNotEmpty &&
            values.toSet().length == values.length) {
          shortcuts = values;
        }
      }
    }

    if (preferences.containsKey(legacyFloatingShortcutsKey)) {
      await Future.wait([
        preferences.setString(musicButtonShortcutsKey, jsonEncode(shortcuts)),
        preferences.remove(legacyFloatingShortcutsKey),
      ]);
    }

    await Future.wait([
      preferences.remove('settings_floating_shortcut_enabled'),
      preferences.remove('settings_floating_shortcut_tap_action'),
      preferences.remove('settings_floating_shortcut_long_press'),
    ]);

    return shortcuts;
  }
}
