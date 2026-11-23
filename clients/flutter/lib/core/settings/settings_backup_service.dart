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
    'settings_discover_enabled',
    'settings_discover_local_lossless',
    'settings_discover_lyrics',
    'settings_discover_auto_queue',
    'settings_discover_artwork',
  };

  static const _integerKeys = <String>{
    'settings_download_concurrency',
    'settings_video_seek_seconds',
  };

  static const _numberKeys = <String>{
    'settings_video_controls_timeout',
    'settings_video_default_speed',
    'settings_video_subtitle_font_size',
  };

  static const _stringKeys = <String>{
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
    'settings_discover_audio_quality',
    'settings_discover_resolver_profile',
    'settings_discover_region',
  };

  static Set<String> get _allowedKeys =>
      {..._booleanKeys, ..._integerKeys, ..._numberKeys, ..._stringKeys};

  static bool _isValidSetting(String key, Object? value) {
    if (_booleanKeys.contains(key)) return value is bool;
    if (key == 'settings_download_concurrency') return value is int && const {1, 2, 3, 5}.contains(value);
    if (key == 'settings_video_seek_seconds') return value is int && const {5, 10, 15, 30}.contains(value);
    if (key == 'settings_video_controls_timeout') return value is num && const [0.0, 2.0, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0].contains(value);

    if (key == 'settings_video_subtitle_font_size') return value is double && value >= 14 && value <= 32;
    if (key == 'settings_video_default_speed') return value is double && const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0].contains(value);
    if (value is! String || value.length > 16384) return false;

    if (key == 'settings_music_button_swipe_left_action' ||
        key == 'settings_music_button_swipe_right_action') {
      return const {'next', 'previous', 'none'}.contains(value);
    }
    if (key == 'settings_now_playing_scrubber_style') {
      return const {'apple', 'wavy', 'classic', 'waveform'}.contains(value);
    }
    if (key == 'settings_now_playing_theme') {
      return const {'apple', 'blur', 'blurCard', 'gradient'}.contains(value);
    }
    if (key == 'settings_video_fit_mode') return const {'contain', 'cover', 'fill'}.contains(value);
    if (key == 'settings_video_fullscreen_orientation') {
      return const {'landscape', 'portrait', 'auto'}.contains(value);
    }
    if (key == 'settings_discover_audio_quality') {
      return const {'best_available', 'balanced', 'data_saver'}.contains(value);
    }
    if (key == 'settings_discover_resolver_profile') {
      return const {'automatic', 'newpipe_first', 'player_api_first'}.contains(value);
    }
    if (key == 'settings_discover_region') {
      return const {
        'IN', 'US', 'GB', 'CA', 'AU', 'JP', 'KR', 'DE', 'FR', 'BR',
        'MX', 'ID', 'PH', 'SG', 'MY', 'TH', 'AE', 'SA', 'ZA', 'NG',
      }.contains(value);
    }

    if (const {
      'settings_home_section_order',
      'settings_navigation_order',
      'settings_navigation_visibility',
      'settings_music_button_shortcuts',
    }.contains(key)) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is! List || decoded.any((item) => item is! String)) return false;
        final items = decoded.cast<String>();
        if (items.toSet().length != items.length) return false;
        if (key == 'settings_home_section_order') {
          return items.length == 5 && items.toSet().containsAll(
            const {'search', 'quick', 'transfers', 'continue', 'recent'},
          );
        }
        if (key == 'settings_navigation_order') {
          return items.length == 4 && items.toSet().containsAll(
            const {'home', 'explore', 'files', 'browse'},
          );
        }
        if (key == 'settings_navigation_visibility') {
          return items.length >= 2 && items.contains('home') &&
              items.every((item) => const {'home', 'explore', 'files', 'browse'}.contains(item));
        }
        const destinations = {
          'explore', 'files', 'music', 'videos', 'photos',
          'documents', 'favorites', 'upload', 'search',
        };
        return items.isNotEmpty && items.every(destinations.contains);
      } on FormatException {
        return false;
      }
    }
    return false;
  }

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
      if (!_isValidSetting(entry.key, value)) {
        throw FormatException('Invalid value for ${entry.key}.');
      }
    }

    final preferences = await SharedPreferences.getInstance();
    final previous = <String, Object?>{
      for (final key in _allowedKeys) key: preferences.get(key),
    };

    try {
      for (final key in _allowedKeys) {
        final value = incoming[key];
        if (value == null) {
          await preferences.remove(key);
          continue;
        }
        final success = switch (value) {
          bool v => await preferences.setBool(key, v),
          int v => await preferences.setInt(key, v),
          double v => await preferences.setDouble(key, v),
          String v => await preferences.setString(key, v),
          _ => false,
        };
        if (!success) throw StateError('Could not restore $key.');
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
              break;
            case int v:
              await preferences.setInt(entry.key, v);
              break;
            case double v:
              await preferences.setDouble(entry.key, v);
              break;
            case String v:
              await preferences.setString(entry.key, v);
              break;
            case List<String> v:
              await preferences.setStringList(entry.key, v);
              break;
          }
        }
      }
      rethrow;
    }
    return incoming.length;
  }
}
