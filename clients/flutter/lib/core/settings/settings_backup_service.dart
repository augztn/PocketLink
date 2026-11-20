import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Portable backup for non-sensitive client preferences only.
///
/// Server profiles, credentials, tokens, filesystem grants and device-specific
/// paths are deliberately excluded.
class SettingsBackupService {
  SettingsBackupService._();

  static const _schemaVersion = 1;
  static const _appId = 'pocketlink';
  static const _maxBackupBytes = 1024 * 1024;

  static const _booleanKeys = <String>{
    'settings_use_liquid_glass',
    'settings_progressive_blur',
    'settings_download_wifi_only',
    'settings_download_auto_resume',
    'settings_video_gestures',
    'settings_video_pinch_zoom',
    'settings_video_tap_toggle',
    'settings_video_subtitle_background',
    'settings_video_auto_fullscreen',
    'settings_music_button_swipe_enabled',
    'settings_music_button_long_press_enabled',
    'settings_now_playing_mini_player',
    'settings_now_playing_gestures',
    'settings_now_playing_stats_for_nerds',
    'settings_home_search',
    'settings_home_transfers',
  };

  static const _integerKeys = <String>{\n  };\n\n  static const _numberKeys = <String>{
    'settings_progressive_blur_strength',
    'settings_download_concurrency',
    'settings_video_controls_timeout',
    'settings_video_seek_seconds',
    'settings_video_default_speed',
    'settings_video_subtitle_font_size',
  };

  static const _stringKeys = <String>{
    'settings_home_quick_actions',
    'settings_home_library',
    'settings_home_recent',
    'settings_home_section_order',
    'settings_navigation_order',
    'settings_navigation_visibility',
    'settings_music_button_shortcuts',
    'settings_music_button_swipe_left_action',
    'settings_music_button_swipe_right_action',
    'settings_now_playing_scrubber_style',
    'settings_now_playing_theme',
    'settings_video_fit_mode',
    'settings_video_fullscreen_orientation',
  };

  static Set<String> get _allowedKeys =>
      {..._booleanKeys, ..._integerKeys, ..._numberKeys, ..._stringKeys};

  static Future<Uint8List> exportBackup() async {
    final preferences = await SharedPreferences.getInstance();
    final settings = <String, Object>{};
    for (final key in _allowedKeys) {
      final value = preferences.get(key);
      if (value != null) settings[key] = value;
    }
    final payload = <String, Object>{
      'app': _appId,
      'schemaVersion': _schemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings,
    };
    final bytes = Uint8List.fromList(utf8.encode(
      const JsonEncoder.withIndent('  ').convert(payload),
    ));
    if (bytes.length > _maxBackupBytes) {
      throw const FormatException('Settings backup is unexpectedly large.');
    }
    return bytes;
  }

  /// Validates the complete document before changing any stored preference.
  /// If a write fails, restores the previous values before returning the error.
  static Future<int> importBackup(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _maxBackupBytes) {
      throw const FormatException('Invalid settings backup size.');
    }

    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != _appId ||
        decoded['schemaVersion'] != _schemaVersion ||
        decoded['createdAt'] is! String ||
        DateTime.tryParse(decoded['createdAt'] as String) == null ||
        decoded['settings'] is! Map<String, dynamic>) {
      throw const FormatException('This is not a supported PocketLink settings backup.');
    }

    final incoming = decoded['settings'] as Map<String, dynamic>;
    if (incoming.length > _allowedKeys.length ||
        incoming.keys.any((key) => !_allowedKeys.contains(key))) {
      throw const FormatException('The backup contains unsupported settings.');
    }

    for (final entry in incoming.entries) {
      final value = entry.value;
      final valid = _booleanKeys.contains(entry.key)
          ? value is bool
          : _numberKeys.contains(entry.key)
              ? value is num && value.isFinite
              : value is String && value.length <= 16384;
      if (!valid) {
        throw FormatException('Invalid value for ${entry.key}.');
      }
    }

    final preferences = await SharedPreferences.getInstance();
    final previous = <String, Object?>{
      for (final key in incoming.keys) key: preferences.get(key),
    };

    try {
      for (final entry in incoming.entries) {
        final value = entry.value;
        final success = switch (value) {
          bool v => await preferences.setBool(entry.key, v),
          int v => await preferences.setInt(entry.key, v),
          double v => await preferences.setDouble(entry.key, v),
          String v => await preferences.setString(entry.key, v),
          _ => false,
        };
        if (!success) throw StateError('Could not restore ${entry.key}.');
      }
    } catch (_) {
      for (final entry in previous.entries) {
        final value = entry.value;
        if (value == null) {
          await preferences.remove(entry.key);
        } else {
          switch (value) {
            case bool v:
              await preferences.setBool(entry.key, v);
            case int v:
              await preferences.setInt(entry.key, v);
            case double v:
              await preferences.setDouble(entry.key, v);
            case String v:
              await preferences.setString(entry.key, v);
            case List<String> v:
              await preferences.setStringList(entry.key, v);
          }
        }
      }
      rethrow;
    }
    return incoming.length;
  }
}
