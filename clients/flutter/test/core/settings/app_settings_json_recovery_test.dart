import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });


  test('malformed Home section JSON does not block navigation preferences', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('settings_home_section_order', '{malformed');
    await preferences.setString(
      'settings_navigation_order',
      '["explore","home","files","browse"]',
    );
    await preferences.setString(
      'settings_navigation_visibility',
      '["home","files"]',
    );

    final settings = AppSettings.instance;
    await settings.reloadPreferences();

    expect(settings.homeSectionOrder, AppSettings.homeSectionDefaults);
    expect(
      settings.navigationOrder,
      const ['explore', 'home', 'files', 'browse'],
    );
    expect(settings.visibleNavigationItems, const {'home', 'files'});
  });

  test('malformed navigation JSON falls back independently', () async {
    final preferences = await SharedPreferences.getInstance();
    final settings = AppSettings.instance;
    await settings.setNavigationLayout(
      order: AppSettings.navigationDefaults,
      visibleItems: AppSettings.navigationDefaults.toSet(),
    );
    await preferences.setString(
      'settings_navigation_order',
      '["home","home","files","browse"]',
    );
    await preferences.setString(
      'settings_navigation_visibility',
      '["home","files"]',
    );
    await settings.reloadPreferences();

    expect(settings.navigationOrder, AppSettings.navigationDefaults);
    expect(settings.visibleNavigationItems, const {'home', 'files'});

    await preferences.setString('settings_navigation_visibility', '{malformed');
    await settings.reloadPreferences();

    expect(settings.navigationOrder, AppSettings.navigationDefaults);
    expect(
      settings.visibleNavigationItems,
      AppSettings.navigationDefaults.toSet(),
    );
  });

  test('mixed-type navigation visibility JSON falls back to defaults', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'settings_navigation_visibility',
      '["home","files",123]',
    );

    final settings = AppSettings.instance;
    await settings.reloadPreferences();

    expect(
      settings.visibleNavigationItems,
      AppSettings.navigationDefaults.toSet(),
    );
  });

}
