import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:progressive_background_blur/progressive_background_blur.dart'
    as shader_blur;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/widgets/feathered_glass_header.dart';
import 'package:pocketlink_client/core/widgets/liquid_glass_pill.dart';
import 'package:pocketlink_client/core/widgets/pocketlink_app_bar.dart';
import 'package:pocketlink_client/core/widgets/progressive_blur.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('header uses one continuous shader backdrop blur', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    expect(find.byType(ProgressiveBlur), findsOneWidget);
    expect(find.byType(shader_blur.ProgressiveBlur), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(BackdropGroup), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    final blur = tester.widget<shader_blur.ProgressiveBlur>(
      find.byType(shader_blur.ProgressiveBlur),
    );
    expect(blur.sigmaStart, 72);
    expect(blur.sigmaEnd, 0);
  });

  testWidgets('continuous blur reverses direction without adding layers',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: ProgressiveBlur(strongestAtBottom: true),
          ),
        ),
      ),
    );

    final blur = tester.widget<shader_blur.ProgressiveBlur>(
      find.byType(shader_blur.ProgressiveBlur),
    );
    expect(blur.begin, Alignment.bottomCenter);
    expect(blur.end, Alignment.topCenter);
    expect(blur.sigmaStart, 72);
    expect(blur.sigmaEnd, 0);
    expect(find.byType(Positioned), findsNothing);
  });

  testWidgets('shader blur converts logical sigma to physical pixels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3),
          child: const Scaffold(
            body: SizedBox(
              height: 100,
              child: ProgressiveBlur(),
            ),
          ),
        ),
      ),
    );

    final blur = tester.widget<shader_blur.ProgressiveBlur>(
      find.byType(shader_blur.ProgressiveBlur),
    );
    expect(blur.sigmaStart, 72);
    expect(blur.sigmaEnd, 0);
  });

  testWidgets('header preserves status bar plus toolbar plus fade-tail geometry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: const Scaffold(body: FeatheredGlassHeaderBackground()),
        ),
      ),
    );
    final bounds = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 192,
    );
    expect(tester.getSize(bounds).height, 192);
  });


  testWidgets('app bar extends the shader from physical top through fade tail',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: Scaffold(
            appBar: const PocketLinkAppBar(
              title: Text('Files'),
              showMoreMenu: false,
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );

    final blurFinder = find.byType(ProgressiveBlur);
    expect(blurFinder, findsOneWidget);
    expect(tester.getTopLeft(blurFinder).dy, 0);
    expect(tester.getSize(blurFinder).height, 192);
    expect(tester.getSize(find.byType(PocketLinkAppBar)).height, 192);
  });

  testWidgets('dark header has a readable default acrylic scrim',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );

    final gradients = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();
    expect(
      gradients.any((gradient) =>
          gradient.colors.first == const Color(0xE6000000) &&
          gradient.colors.last == Colors.transparent),
      isTrue,
    );
  });

  testWidgets('custom dark tint remains supported', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(
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
    final gradients = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();
    expect(
      gradients.any((gradient) =>
          gradient.colors.length == 5 &&
          gradient.colors.first == const Color(0xD9000000) &&
          gradient.colors.last == Colors.transparent),
      isTrue,
    );
  });

  testWidgets('Liquid Glass UI off still disables other glass surfaces',
      (tester) async {
    await tester.runAsync(
      () => AppSettings.instance.setUseLiquidGlass(false),
    );
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
}
