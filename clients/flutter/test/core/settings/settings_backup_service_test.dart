import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/settings_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings_use_liquid_glass': true,
      'settings_progressive_blur': true,
      'settings_progressive_blur_strength': 72.5,
      'settings_discover_enabled': false,
      'settings_discover_artwork': false,
      'settings_discover_audio_quality': 'balanced',
      'settings_discover_resolver_profile': 'player_api_first',
      'settings_discover_region': 'JP',
      'saved_server_profiles': '[{"host":"private"}]',
    });
  });

  test('export includes supported preferences and excludes server data', () async {
    final bytes = await SettingsBackupService.exportBackup();
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final settings = payload['settings'] as Map<String, dynamic>;

    expect(payload['app'], 'pocketlink');
    expect(payload['schemaVersion'], 1);
    expect(settings['settings_progressive_blur_strength'], 72.5);
    expect(settings['settings_discover_enabled'], isFalse);
    expect(settings['settings_discover_artwork'], isFalse);
    expect(settings['settings_discover_audio_quality'], 'balanced');
    expect(settings['settings_discover_resolver_profile'], 'player_api_first');
    expect(settings['settings_discover_region'], 'JP');
    expect(settings.containsKey('saved_server_profiles'), isFalse);
  });

  test('import validates then restores supported preferences', () async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'app': 'pocketlink',
      'schemaVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': {
        'settings_use_liquid_glass': false,
        'settings_progressive_blur_strength': 35.0,
        'settings_discover_audio_quality': 'data_saver',
        'settings_discover_resolver_profile': 'newpipe_first',
        'settings_discover_region': 'US',
      },
    })));

    final restored = await SettingsBackupService.importBackup(bytes);
    final preferences = await SharedPreferences.getInstance();

    expect(restored, 2);
    expect(preferences.getBool('settings_use_liquid_glass'), isFalse);
    expect(preferences.getDouble('settings_progressive_blur_strength'), 35.0);
    expect(preferences.getString('settings_discover_audio_quality'), 'data_saver');
    expect(preferences.getString('settings_discover_resolver_profile'), 'newpipe_first');
    expect(preferences.getString('settings_discover_region'), 'US');
    expect(preferences.getString('saved_server_profiles'), contains('private'));
  });

  test('invalid backup is rejected without changing preferences', () async {
    final preferences = await SharedPreferences.getInstance();
    final original = preferences.getBool('settings_use_liquid_glass');

    await expectLater(
      SettingsBackupService.importBackup(
        Uint8List.fromList(utf8.encode('{"app":"not-pocketlink"}')),
      ),
      throwsFormatException,
    );

    expect(preferences.getBool('settings_use_liquid_glass'), original);
  });

  test('unknown keys and incorrect value types are rejected', () async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'app': 'pocketlink',
      'schemaVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': {'saved_server_profiles': 'must-not-import'},
    })));

    await expectLater(
      SettingsBackupService.importBackup(bytes),
      throwsFormatException,
    );
  });
}
