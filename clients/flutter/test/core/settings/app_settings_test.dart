import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:homeserver_client/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Host PocketLink layout defaults to tabs and persists normal mode', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;

    await settings.load();
    expect(settings.hostSetupTabbedLayout, isTrue);

    await settings.setHostSetupTabbedLayout(false);
    expect(settings.hostSetupTabbedLayout, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('settings_host_setup_tabbed_layout'), isFalse);
  });
}
