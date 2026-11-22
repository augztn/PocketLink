import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/widgets/liquid_glass_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await AppSettings.instance.setUseLiquidGlass(false);
  });

  testWidgets('zero glass intensity removes the surface and backdrop filter', (
    tester,
  ) async {
    await AppSettings.instance.setUseLiquidGlass(true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidGlassSurface(
            radius: BorderRadius.circular(20),
            intensity: 0,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass intensity remains a direct child of the backdrop filter', (
    tester,
  ) async {
    await AppSettings.instance.setUseLiquidGlass(true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmokedGlassSurface(
            radius: BorderRadius.circular(20),
            refractive: true,
            intensity: 0.5,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
