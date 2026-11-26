import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('navigation layout persists reordered destinations and visibility', () async {
    final settings = AppSettings.instance;
    const order = ['home', 'files', 'browse', 'explore'];
    const visible = {'home', 'files', 'browse'};

    await settings.setNavigationLayout(order: order, visibleItems: visible);

    expect(settings.navigationOrder, order);
    expect(settings.visibleNavigationItems, visible);
    expect(settings.navigationLayoutIsDefault, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings_navigation_order'),
        '["home","files","browse","explore"]');
    expect(preferences.getString('settings_navigation_visibility'),
        '["home","files","browse"]');
  });

  test('navigation layout rejects invalid visibility but allows Home anywhere', () async {
    final settings = AppSettings.instance;

    await expectLater(
      settings.setNavigationLayout(
        order: AppSettings.navigationDefaults,
        visibleItems: const {'home'},
      ),
      throwsArgumentError,
    );
    await settings.setNavigationLayout(
      order: const ['explore', 'home', 'files', 'browse'],
      visibleItems: const {'home', 'explore'},
    );
    expect(settings.navigationOrder,
        const ['explore', 'home', 'files', 'browse']);
  });

  test('reset restores default order and all destinations', () async {
    final settings = AppSettings.instance;
    await settings.setNavigationLayout(
      order: const ['home', 'files', 'browse', 'explore'],
      visibleItems: const {'home', 'files'},
    );

    await settings.resetNavigationLayout();

    expect(settings.navigationOrder, AppSettings.navigationDefaults);
    expect(settings.visibleNavigationItems, AppSettings.navigationDefaults.toSet());
    expect(settings.navigationLayoutIsDefault, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings_navigation_order'), isNull);
    expect(preferences.getString('settings_navigation_visibility'), isNull);
  });
  test('Home defaults prioritize actions and recent activity', () {
    expect(
      AppSettings.homeSectionDefaults,
      const ['quick', 'continue', 'recent', 'transfers', 'search'],
    );
  });

  test('Home section order persists and rejects incomplete layouts', () async {
    final settings = AppSettings.instance;
    const order = ['recent', 'search', 'continue', 'quick', 'transfers'];

    await settings.setHomeSectionOrder(order);

    expect(settings.homeSectionOrder, order);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings_home_section_order'),
        '["recent","search","continue","quick","transfers"]');

    await expectLater(
      settings.setHomeSectionOrder(const ['search', 'quick']),
      throwsArgumentError,
    );
  });

  test('existing default Music shortcuts migrate to include Drives', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'settings_music_button_shortcuts',
      '["photos","music","videos","documents","files","search"]',
    );

    final settings = AppSettings.instance;
    await settings.reloadPreferences();

    expect(settings.musicButtonShortcuts, AppSettings.musicButtonShortcutDefaults);
    expect(
      preferences.getString('settings_music_button_shortcuts'),
      '["photos","music","videos","documents","files","search","drives"]',
    );
  });

  test('Music button shortcuts persist, validate and reset', () async {
    final settings = AppSettings.instance;
    const shortcuts = ['music', 'files', 'photos', 'upload', 'drives'];

    await settings.setMusicButtonShortcuts(shortcuts);
    expect(settings.musicButtonShortcuts, shortcuts);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings_music_button_shortcuts'),
        '["music","files","photos","upload","drives"]');

    await expectLater(
      settings.setMusicButtonShortcuts(const ['music', 'music']),
      throwsArgumentError,
    );
    await expectLater(
      settings.setMusicButtonShortcuts(const ['unknown']),
      throwsArgumentError,
    );
    await expectLater(
      settings.setMusicButtonShortcuts(const []),
      throwsArgumentError,
    );

    await settings.resetMusicButtonShortcuts();
    expect(settings.musicButtonShortcuts, AppSettings.musicButtonShortcutDefaults);
    expect(preferences.getString('settings_music_button_shortcuts'), isNull);
  });

  test('stats for nerds setting persists, can be disabled and resets enabled', () async {
    final settings = AppSettings.instance;
    await settings.setNowPlayingOptions(statsForNerds: true);
    expect(settings.showStatsForNerds, isTrue);

    await settings.setNowPlayingOptions(statsForNerds: false);
    expect(settings.showStatsForNerds, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('settings_now_playing_stats_for_nerds'),
      isFalse,
    );

    await settings.resetNowPlayingOptions();
    expect(settings.showStatsForNerds, isTrue);
    expect(
      preferences.getBool('settings_now_playing_stats_for_nerds'),
      isNull,
    );
  });
  test('Music button swipe and hold preferences validate and persist', () async {
    final settings = AppSettings.instance;

    await settings.setMusicButtonOptions(
      swipeEnabled: true,
      swipeLeftAction: 'next',
      swipeRightAction: 'previous',
      longPressEnabled: true,
    );

    expect(settings.musicButtonSwipeEnabled, isTrue);
    expect(settings.musicButtonSwipeLeftAction, 'next');
    expect(settings.musicButtonSwipeRightAction, 'previous');
    expect(settings.musicButtonLongPressEnabled, isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('settings_music_button_swipe_enabled'), isTrue);
    expect(preferences.getString('settings_music_button_swipe_left_action'), 'next');
    expect(preferences.getString('settings_music_button_swipe_right_action'), 'previous');
    expect(preferences.getBool('settings_music_button_long_press_enabled'), isTrue);

    await expectLater(
      settings.setMusicButtonOptions(swipeLeftAction: 'invalid'),
      throwsArgumentError,
    );
    await expectLater(
      settings.setMusicButtonOptions(swipeRightAction: 'invalid'),
      throwsArgumentError,
    );

    await settings.setMusicButtonOptions(
      swipeEnabled: false,
      swipeLeftAction: 'none',
      swipeRightAction: 'none',
      longPressEnabled: false,
    );
    expect(settings.musicButtonSwipeEnabled, isFalse);
    expect(settings.musicButtonSwipeLeftAction, 'none');
    expect(settings.musicButtonSwipeRightAction, 'none');
    expect(settings.musicButtonLongPressEnabled, isFalse);

    await settings.resetMusicButtonOptions();
    expect(settings.musicButtonSwipeEnabled, isTrue);
    expect(settings.musicButtonSwipeLeftAction, 'next');
    expect(settings.musicButtonSwipeRightAction, 'previous');
    expect(settings.musicButtonLongPressEnabled, isTrue);
    expect(preferences.getBool('settings_music_button_swipe_enabled'), isNull);
    expect(preferences.getString('settings_music_button_swipe_left_action'), isNull);
    expect(preferences.getString('settings_music_button_swipe_right_action'), isNull);
    expect(preferences.getBool('settings_music_button_long_press_enabled'), isNull);
  });

}
