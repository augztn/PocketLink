import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/widgets/feathered_glass_header.dart';
import 'package:pocketlink_client/core/widgets/liquid_glass_pill.dart';
import 'package:pocketlink_client/core/widgets/pocketlink_scaffold.dart';

Widget _withScrolledHeader(Widget child) => PocketLinkScrollOffsetScope(
      offset: ValueNotifier<double>(24),
      child: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('transparent header blur is enabled by default', () {
    expect(AppSettings.instance.progressiveBlurEnabled, isTrue);
  });

  test('progressive header blur preference persists when toggled', () async {
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

  testWidgets('Liquid Glass UI off disables floating glass blur and rim', (tester) async {
    await tester.runAsync(() async {
      await AppSettings.instance.setUseLiquidGlass(false);
      await AppSettings.instance.setProgressiveBlurEnabled(true);
    });

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

  testWidgets('Progressive Blur off does not change original Liquid Glass surfaces', (tester) async {
    await tester.runAsync(() async {
      await AppSettings.instance.setUseLiquidGlass(true);
      await AppSettings.instance.setProgressiveBlurEnabled(false);
    });

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

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('Liquid Glass continues blurring dock and mini-player independently', (tester) async {
    await tester.runAsync(() async {
      await AppSettings.instance.setUseLiquidGlass(true);
      await AppSettings.instance.setProgressiveBlurEnabled(true);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LiquidGlassSurface(
                radius: BorderRadius.all(Radius.circular(16)),
                child: Text('Dock'),
              ),
              SmokedGlassSurface(
                radius: BorderRadius.all(Radius.circular(16)),
                child: Text('Mini player'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('header blur is independent of the Liquid Glass UI toggle', (tester) async {
    await tester.runAsync(() async {
      await AppSettings.instance.setUseLiquidGlass(false);
      await AppSettings.instance.setProgressiveBlurEnabled(true);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FeatheredGlassHeaderBackground(),
              SmokedGlassSurface(
                radius: BorderRadius.all(Radius.circular(16)),
                child: Text('Mini player'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.runAsync(
      () => AppSettings.instance.setUseLiquidGlass(true),
    );
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('header applies frosted blur when enabled', (tester) async {
    await tester.runAsync(
      () => AppSettings.instance.setProgressiveBlurEnabled(true),
    );

    await tester.pumpWidget(
      _withScrolledHeader(
        const MaterialApp(
          home: Scaffold(body: FeatheredGlassHeaderBackground()),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('header blur remains active when reduced motion is enabled', (tester) async {
    await tester.runAsync(
      () => AppSettings.instance.setProgressiveBlurEnabled(true),
    );

    await tester.pumpWidget(
      _withScrolledHeader(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(body: FeatheredGlassHeaderBackground()),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('turning header blur off preserves its translucent tint', (tester) async {
    await tester.runAsync(
      () => AppSettings.instance.setProgressiveBlurEnabled(false),
    );

    await tester.pumpWidget(
      const MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();
    expect(
      gradients.any((gradient) =>
          gradient.colors.first == const Color(0x66000000) &&
          gradient.colors.last == Colors.transparent),
      isTrue,
    );
  });

  testWidgets('progressive blur off removes header filters immediately', (tester) async {
    await tester.runAsync(
      () => AppSettings.instance.setProgressiveBlurEnabled(true),
    );

    await tester.pumpWidget(
      _withScrolledHeader(
        const MaterialApp(
          home: Scaffold(body: FeatheredGlassHeaderBackground()),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.runAsync(
      () => AppSettings.instance.setProgressiveBlurEnabled(false),
    );
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('header action buttons follow the Liquid Glass toggle', (tester) async {
    await tester.runAsync(() async {
      await AppSettings.instance.setProgressiveBlurEnabled(true);
      await AppSettings.instance.setUseLiquidGlass(false);
    });

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

    await tester.runAsync(
      () => AppSettings.instance.setUseLiquidGlass(true),
    );
    await tester.pump();

    expect(find.byType(BackdropFilter), findsOneWidget);
  });
  testWidgets('Progressive Blur off affects only the header, not Liquid Glass surfaces', (tester) async {
    await tester.runAsync(() async {
      await AppSettings.instance.setUseLiquidGlass(true);
      await AppSettings.instance.setProgressiveBlurEnabled(false);
    });

    await tester.pumpWidget(
      _withScrolledHeader(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FeatheredGlassHeaderBackground(),
                LiquidGlassSurface(
                  radius: BorderRadius.all(Radius.circular(16)),
                  child: Text('Dock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The dock keeps its original Liquid Glass blur; the header contributes none.
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

}
