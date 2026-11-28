import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.reloadPreferences();
  });

  test('first-screen Discover visibility defaults on and persists', () async {
    final settings = AppSettings.instance;
    expect(settings.showDiscoverOnWelcome, isTrue);

    await settings.setShowDiscoverOnWelcome(false);
    expect(settings.showDiscoverOnWelcome, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('settings_show_discover_on_welcome'), isFalse);

    await settings.reloadPreferences();
    expect(settings.showDiscoverOnWelcome, isFalse);
    await settings.setShowDiscoverOnWelcome(true);
    expect(settings.showDiscoverOnWelcome, isTrue);
  });

  test('Discover preferences persist and reload', () async {
    final settings = AppSettings.instance;
    await settings.setDiscoverOptions(
      enabled: false,
      localLossless: false,
      lyrics: false,
      autoQueue: false,
      artwork: false,
      spotlight: false,
      artistGrid: false,
    );
    await settings.setDiscoverPlaybackOptions(
      audioQuality: 'data_saver',
      resolverProfile: 'player_api_first',
      region: 'JP',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(settings.discoverEnabled, isFalse);
    expect(settings.discoverLocalLossless, isFalse);
    expect(settings.discoverLyrics, isFalse);
    expect(settings.discoverAutoQueue, isFalse);
    expect(settings.discoverArtwork, isFalse);
    expect(settings.discoverSpotlight, isFalse);
    expect(settings.discoverArtistGrid, isFalse);
    expect(settings.discoverAudioQuality, 'data_saver');
    expect(settings.discoverResolverProfile, 'player_api_first');
    expect(settings.discoverRegion, 'JP');
    expect(preferences.getBool('settings_discover_enabled'), isFalse);
    expect(preferences.getBool('settings_discover_spotlight'), isFalse);
    expect(preferences.getBool('settings_discover_artist_grid'), isFalse);
    expect(preferences.getString('settings_discover_audio_quality'), 'data_saver');
    expect(preferences.getString('settings_discover_resolver_profile'), 'player_api_first');
    expect(preferences.getString('settings_discover_region'), 'JP');

    await settings.reloadPreferences();
    expect(settings.discoverEnabled, isFalse);
    expect(settings.discoverLocalLossless, isFalse);
    expect(settings.discoverLyrics, isFalse);
    expect(settings.discoverAutoQueue, isFalse);
    expect(settings.discoverArtwork, isFalse);
    expect(settings.discoverSpotlight, isFalse);
    expect(settings.discoverArtistGrid, isFalse);
    expect(settings.discoverAudioQuality, 'data_saver');
    expect(settings.discoverResolverProfile, 'player_api_first');
    expect(settings.discoverRegion, 'JP');
    await expectLater(
      settings.setDiscoverPlaybackOptions(audioQuality: 'lossless'),
      throwsArgumentError,
    );
    await expectLater(
      settings.setDiscoverPlaybackOptions(resolverProfile: 'fake'),
      throwsArgumentError,
    );
    await expectLater(
      settings.setDiscoverPlaybackOptions(region: 'ZZ'),
      throwsArgumentError,
    );
  });

  test('Liquid Glass defaults off and preference persists', () async {
    final settings = AppSettings.instance;
    expect(settings.useLiquidGlass, isFalse);

    await settings.setUseLiquidGlass(true);

    final preferences = await SharedPreferences.getInstance();
    expect(settings.useLiquidGlass, isTrue);
    expect(preferences.getBool('settings_use_liquid_glass'), isTrue);

    await settings.setUseLiquidGlass(false);
    expect(settings.useLiquidGlass, isFalse);
    expect(preferences.getBool('settings_use_liquid_glass'), isFalse);
  });

  test('media settings persist, validate and reset through the facade', () async {
    final settings = AppSettings.instance;

    await settings.setDownloadOptions(concurrency: 3, wifiOnly: true, autoResume: false);
    await settings.setNowPlayingOptions(miniPlayer: false, gestures: false, statsForNerds: false);
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
    expect(preferences.getString('settings_video_fit_mode'), 'cover');

    await expectLater(settings.setDownloadOptions(concurrency: 4), throwsArgumentError);

    await settings.resetNowPlayingOptions();
    await settings.resetVideoPlayerOptions();
    expect(settings.showMiniPlayer, isTrue);
    expect(settings.enableNowPlayingGestures, isTrue);
    expect(settings.showStatsForNerds, isTrue);
    expect(settings.videoSeekSeconds, 10);
    expect(settings.videoDefaultSpeed, 1);
    expect(settings.videoFitMode, 'contain');
    expect(settings.videoFullscreenOrientation, 'landscape');
    expect(preferences.getInt('settings_video_seek_seconds'), isNull);
  });
}
