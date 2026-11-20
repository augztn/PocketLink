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
