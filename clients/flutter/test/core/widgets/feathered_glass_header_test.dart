import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/widgets/feathered_glass_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('progressive blur is disabled by default', () {
    expect(AppSettings.instance.progressiveBlurEnabled, isFalse);
  });

  test('progressive blur strength defaults to 55 percent', () {
    expect(AppSettings.instance.progressiveBlurStrength, 55);
  });

  testWidgets('progressive blur strength is clamped, persisted and validated', (tester) async {
    await AppSettings.instance.setProgressiveBlurStrength(72.5);
    expect(AppSettings.instance.progressiveBlurStrength, 72.5);
    expect(
      (await SharedPreferences.getInstance()).getDouble('settings_progressive_blur_strength'),
      72.5,
    );
    await expectLater(
      AppSettings.instance.setProgressiveBlurStrength(101),
      throwsArgumentError,
    );
  });

  testWidgets('progressive blur preference persists when toggled', (tester) async {
    await AppSettings.instance.setProgressiveBlurEnabled(true);
    expect(AppSettings.instance.progressiveBlurEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('settings_progressive_blur'),
      isTrue,
    );

    await AppSettings.instance.setProgressiveBlurEnabled(false);
    expect(AppSettings.instance.progressiveBlurEnabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool('settings_progressive_blur'),
      isFalse,
    );
  });

  testWidgets('progressive header uses staged blur when enabled', (tester) async {
    await AppSettings.instance.setProgressiveBlurEnabled(true);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('zero blur strength removes backdrop filters while enabled', (tester) async {
    await AppSettings.instance.setProgressiveBlurEnabled(true);
    await AppSettings.instance.setProgressiveBlurStrength(0);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('progressive blur off removes backdrop filters immediately', (tester) async {
    await AppSettings.instance.setProgressiveBlurEnabled(true);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));

    await AppSettings.instance.setProgressiveBlurEnabled(false);
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('glass header buttons disable their filter in fallback mode', (tester) async {
    await AppSettings.instance.setProgressiveBlurEnabled(false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassCircleButton(
            tooltip: 'Back',
            onPressed: null,
            child: Icon(Icons.arrow_back_rounded),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);

    await AppSettings.instance.setProgressiveBlurEnabled(true);
    await tester.pump();

    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
