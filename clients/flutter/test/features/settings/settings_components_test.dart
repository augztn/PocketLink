import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/settings/widgets/settings_components.dart';

void main() {
  group('settingsSearchableText', () {
    test('indexes standard setting title and subtitle', () {
      const tile = SettingsTile(
        title: 'Player style',
        subtitle: 'PocketLink, Poster or Lyrics',
      );

      final text = settingsSearchableText(tile);

      expect(text, contains('Player style'));
      expect(text, contains('Poster'));
    });

    test('indexes switch title and subtitle', () {
      const tile = SwitchListTile(
        title: Text('Mini-player'),
        subtitle: Text('Show compact playback controls'),
        value: true,
        onChanged: null,
      );

      final text = settingsSearchableText(tile);

      expect(text, contains('Mini-player'));
      expect(text, contains('playback controls'));
    });

    test('indexes nested parent and dependent setting rows', () {
      final group = SettingsNestedGroup(
        parent: const SwitchListTile(
          title: Text('Animations'),
          value: true,
          onChanged: null,
        ),
        children: const [
          SettingsTile(title: 'Page transitions'),
          SettingsTile(title: 'Lyrics animations'),
        ],
      );

      final text = settingsSearchableText(group);

      expect(text, contains('Animations'));
      expect(text, contains('Page transitions'));
      expect(text, contains('Lyrics animations'));
    });
  });
}
