import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/widgets/feathered_glass_header.dart';
import 'package:pocketlink_client/core/widgets/liquid_glass_pill.dart';
import 'package:pocketlink_client/core/widgets/progressive_blur.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('header uses eased grouped blur and an alpha fade mask', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );
    expect(find.byType(ProgressiveBlur), findsOneWidget);
    expect(find.byType(BackdropGroup), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNWidgets(18));
    final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    expect(mask.blendMode, BlendMode.dstIn);
  });

  testWidgets('progressive blur supports reversed direction', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: ProgressiveBlur(steps: 4, strongestAtBottom: true),
          ),
        ),
      ),
    );
    final bands = tester.widgetList<Positioned>(find.byType(Positioned)).toList();
    expect(bands, hasLength(4));
    expect(bands.first.top, 75);
    expect(bands.last.top, 0);
  });

  test('blur intensity follows an ease-in-out curve', () {
    expect(ProgressiveBlur.intensityAt(0), 1);
    expect(ProgressiveBlur.intensityAt(0.5), closeTo(0.5, 1e-9));
    expect(ProgressiveBlur.intensityAt(1), 0);
    var previous = 1.0;
    for (var index = 0; index <= 100; index++) {
      final intensity = ProgressiveBlur.intensityAt(index / 100);
      expect(intensity, lessThanOrEqualTo(previous));
      previous = intensity;
    }
    expect(ProgressiveBlur.intensityAt(0.1), greaterThan(0.9));
    expect(ProgressiveBlur.intensityAt(0.9), lessThan(0.1));
  });

  testWidgets('header preserves status bar plus toolbar plus fade-tail geometry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: const Scaffold(body: FeatheredGlassHeaderBackground()),
        ),
      ),
    );
    final bounds = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 96,
    );
    expect(tester.getSize(bounds).height, 96);
  });

  test('fade mask stays opaque through 60 percent then eases to transparent', () {
    expect(FeatheredGlassHeaderBackground.fadeMaskAlphaAt(0), 1);
    expect(FeatheredGlassHeaderBackground.fadeMaskAlphaAt(0.6), 1);
    expect(FeatheredGlassHeaderBackground.fadeMaskAlphaAt(1), 0);
    var previous = 1.0;
    for (var index = 0; index <= 100; index++) {
      final alpha = FeatheredGlassHeaderBackground.fadeMaskAlphaAt(index / 100);
      expect(alpha, lessThanOrEqualTo(previous));
      previous = alpha;
    }
    expect(FeatheredGlassHeaderBackground.fadeMaskAlphaAt(0.8), greaterThan(0));
    expect(FeatheredGlassHeaderBackground.fadeMaskAlphaAt(0.98), lessThan(0.01));
  });

  test('fade mask uses nine alpha samples and can reverse direction', () {
    final gradient = FeatheredGlassHeaderBackground.fadeMaskGradient();
    expect(gradient.colors, hasLength(9));
    expect(gradient.colors.first.a, 1);
    expect(gradient.colors.last.a, 0);
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);

    final reversed = FeatheredGlassHeaderBackground.fadeMaskGradient(
      strongestAtBottom: true,
    );
    expect(reversed.begin, Alignment.bottomCenter);
    expect(reversed.end, Alignment.topCenter);
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
    expect(gradients.any((gradient) =>
      gradient.colors.length == 5 &&
      gradient.colors.first == const Color(0xD9000000) &&
      gradient.colors.last == Colors.transparent), isTrue);
  });

  for (final dpr in [2.625, 3.0, 3.5]) {
    testWidgets('blur bands align and overlap at devicePixelRatio $dpr', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: dpr),
            child: const Scaffold(
              body: SizedBox(height: 96, child: ProgressiveBlur(steps: 6)),
            ),
          ),
        ),
      );
      final bands = tester.widgetList<Positioned>(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Positioned),
        ),
      ).toList()
        ..sort((a, b) => a.top!.compareTo(b.top!));
      expect(bands, hasLength(6));
      for (final band in bands) {
        final topPixels = band.top! * dpr;
        final bottomPixels = (band.top! + band.height!) * dpr;
        expect(topPixels, closeTo(topPixels.roundToDouble(), 1e-6));
        expect(bottomPixels, closeTo(bottomPixels.roundToDouble(), 1e-6));
      }
      for (var index = 1; index < bands.length; index++) {
        final previousBottom = bands[index - 1].top! + bands[index - 1].height!;
        expect(bands[index].top!, lessThanOrEqualTo(previousBottom + 1e-6));
      }
    });
  }

  testWidgets('Liquid Glass UI off still disables other glass surfaces', (tester) async {
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
}
