import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.reloadPreferences();
  });

  test('appearance settings persist and validate through the facade', () async {
    final settings = AppSettings.instance;

    await settings.setUseLiquidGlass(true);
    await settings.setProgressiveBlurEnabled(true);
    await settings.setProgressiveBlurStrength(72.5);

    final preferences = await SharedPreferences.getInstance();
    expect(settings.useLiquidGlass, isTrue);
    expect(settings.progressiveBlurEnabled, isTrue);
    expect(settings.progressiveBlurStrength, 72.5);
    expect(preferences.getBool('settings_use_liquid_glass'), isTrue);
    expect(preferences.getBool('settings_progressive_blur'), isTrue);
    expect(preferences.getDouble('settings_progressive_blur_strength'), 72.5);

    await expectLater(settings.setProgressiveBlurStrength(-1), throwsArgumentError);
    await expectLater(settings.setProgressiveBlurStrength(double.nan), throwsArgumentError);
  });

  test('media settings persist, validate and reset through the facade', () async {
    final settings = AppSettings.instance;

    await settings.setDownloadOptions(concurrency: 3, wifiOnly: true, autoResume: false);
    await settings.setNowPlayingOptions(miniPlayer: false, gestures: false, statsForNerds: false);
    await settings.setNowPlayingScrubberStyle('waveform');
    await settings.setNowPlayingTheme('gradient');
    await settings.setVideoPlayerOptions(
      controlsTimeoutSeconds: 5,
      seekSeconds: 15,
      defaultSpeed: 1.5,
      fitMode: 'cover',
      gesturesEnabled: false,
      pinchZoomEnabled: false,
      tapToTogglePlayback: true,
      subtitleFontSize: 24,
      subtitleBackground: false,
      autoFullscreen: true,
      fullscreenOrientation: 'portrait',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(settings.downloadConcurrency, 3);
    expect(settings.downloadWifiOnly, isTrue);
    expect(settings.downloadAutoResume, isFalse);
    expect(settings.showMiniPlayer, isFalse);
    expect(settings.enableNowPlayingGestures, isFalse);
    expect(settings.showStatsForNerds, isFalse);
    expect(settings.nowPlayingScrubberStyle, 'waveform');
    expect(settings.nowPlayingTheme, 'gradient');
    expect(settings.videoControlsTimeoutSeconds, 5);
    expect(settings.videoSeekSeconds, 15);
    expect(settings.videoDefaultSpeed, 1.5);
    expect(settings.videoFitMode, 'cover');
    expect(settings.videoGesturesEnabled, isFalse);
    expect(settings.videoPinchZoomEnabled, isFalse);
    expect(settings.videoTapToTogglePlayback, isTrue);
    expect(settings.videoSubtitleFontSize, 24);
    expect(settings.videoSubtitleBackground, isFalse);
    expect(settings.videoAutoFullscreen, isTrue);
    expect(settings.videoFullscreenOrientation, 'portrait');
    expect(preferences.getInt('settings_download_concurrency'), 3);
    expect(preferences.getString('settings_now_playing_theme'), 'gradient');
    expect(preferences.getString('settings_video_fit_mode'), 'cover');

    await expectLater(settings.setDownloadOptions(concurrency: 4), throwsArgumentError);
    await expectLater(settings.setNowPlayingTheme('unsupported'), throwsArgumentError);

    await settings.resetNowPlayingOptions();
    await settings.resetVideoPlayerOptions();
    expect(settings.showMiniPlayer, isTrue);
    expect(settings.enableNowPlayingGestures, isTrue);
    expect(settings.showStatsForNerds, isTrue);
    expect(settings.nowPlayingTheme, 'apple');
    expect(settings.videoSeekSeconds, 10);
    expect(settings.videoDefaultSpeed, 1);
    expect(settings.videoFitMode, 'contain');
    expect(settings.videoFullscreenOrientation, 'landscape');
    expect(preferences.getString('settings_now_playing_theme'), isNull);
    expect(preferences.getInt('settings_video_seek_seconds'), isNull);
  });
}
