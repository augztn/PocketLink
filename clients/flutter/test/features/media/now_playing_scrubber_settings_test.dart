import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/features/media/now_playing_scrubber.dart';

void main() {
  final settings = AppSettings.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.resetNowPlayingOptions();
  });

  test('Apple Capsule is the default scrubber style', () {
    expect(settings.nowPlayingScrubberStyle, 'apple');
    expect(
      NowPlayingScrubberStyle.fromKey('unknown'),
      NowPlayingScrubberStyle.appleCapsule,
    );
  });

  test('selected scrubber style persists without resetting playback', () async {
    await settings.setNowPlayingScrubberStyle('wavy');

    final preferences = await SharedPreferences.getInstance();
    expect(settings.nowPlayingScrubberStyle, 'wavy');
    expect(
      preferences.getString('settings_now_playing_scrubber_style'),
      'wavy',
    );
  });

  test('unsupported scrubber styles are rejected', () {
    expect(
      () => settings.setNowPlayingScrubberStyle('unsupported'),
      throwsArgumentError,
    );
  });
}
