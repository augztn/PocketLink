import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:homeserver_client/core/settings/app_settings.dart';

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

}
