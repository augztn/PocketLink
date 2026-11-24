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

  testWidgets('header always renders Mochy progressive blur bands', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FeatheredGlassHeaderBackground()),
      ),
    );
    expect(find.byType(BackdropFilter), findsNWidgets(14));
    expect(find.byType(ShaderMask), findsNothing);
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

  testWidgets('dark and light themes use a five-stop scrim fading to zero alpha', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: FeatheredGlassHeaderBackground()),
        ),
      );
      final gradients = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>();
      expect(gradients.first.colors, hasLength(5));
      expect(gradients.first.colors.last.alpha, 0);
    }
  });

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
