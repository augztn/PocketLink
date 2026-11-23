import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/widgets/feathered_glass_header.dart';
import 'package:pocketlink_client/core/widgets/liquid_glass_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('progressive blur is enabled by default', () {
    expect(AppSettings.instance.progressiveBlurEnabled, isTrue);
  });

  test('progressive blur strength defaults to 55 percent', () {
    expect(AppSettings.instance.progressiveBlurStrength, 55);
  });

  test('progressive blur strength is clamped, persisted and validated', () async {
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

  test('progressive blur preference persists when toggled', () async {
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

  testWidgets('Liquid Glass UI off disables LiquidGlassSurface blur', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setUseLiquidGlass(false));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiquidGlassSurface(
            radius: BorderRadius.all(Radius.circular(16)),
            refractive: true,
            child: Text('Dock'),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('Liquid Glass UI off disables SmokedGlassSurface blur and rim', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setUseLiquidGlass(false));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SmokedGlassSurface(
            radius: BorderRadius.all(Radius.circular(16)),
            refractive: true,
            child: Text('Mini player'),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
      findsNothing,
    );
  });

  testWidgets('Liquid Glass UI on enables shared surface blur', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setUseLiquidGlass(true));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiquidGlassSurface(
            radius: BorderRadius.all(Radius.circular(16)),
            child: Text('Dock'),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('progressive header uses staged blur when enabled', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurStrength(55));
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(true));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(5));
  });

  testWidgets('progressive blur remains active when reduced motion is enabled', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurStrength(55));
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(true));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: FeatheredGlassHeaderBackground()),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('custom dark tint is retained when progressive blur is disabled', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(false));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: FeatheredGlassHeaderBackground(
            darkTint: [
              Color(0xD9000000),
              Color(0x66000000),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );

    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();
    expect(
      gradients.any((gradient) => gradient.colors.length == 3 &&
          gradient.colors[0] == const Color(0xD9000000) &&
          gradient.colors[1] == const Color(0x66000000) &&
          gradient.colors[2] == Colors.transparent),
      isTrue,
    );
  });

  testWidgets('zero blur strength removes backdrop filters while enabled', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(true));
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurStrength(0));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('progressive blur off removes backdrop filters immediately', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurStrength(55));
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(true));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));

    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(false));
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('glass header buttons disable their filter in fallback mode', (tester) async {
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurStrength(55));
    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(false));

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

    await tester.runAsync(() => AppSettings.instance.setProgressiveBlurEnabled(true));
    await tester.pump();

    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
