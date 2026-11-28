import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_repository.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_viewport.dart';
import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {

  testWidgets('active timestamped lyric remains crisp white', (tester) async {
    final document = LyricsDocument(
      providerId: 'test',
      providerName: 'Test',
      synced: true,
      lines: const [
        LyricsLine(0, 'Previous line'),
        LyricsLine(10000, 'Active line'),
        LyricsLine(20000, 'Next line'),
      ],
    );

    tester.view.physicalSize = const Size(432, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsViewport(
            document: document,
            position: const Duration(seconds: 15),
            results: const {},
            providers: const [],
            onSeek: (_) {},
            onChooseProvider: () {},
            onToggleTranslation: () {},
            onRetry: () {},
            translationEnabled: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeLine = find.text('Active line');
    expect(activeLine, findsOneWidget);
    final text = tester.widget<Text>(activeLine);
    expect(text.style?.color, Colors.white);

    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: activeLine,
        matching: find.byType(AnimatedOpacity),
      ).first,
    );
    expect(opacity.opacity, 1);

    final blur = tester.widget<ImageFiltered>(
      find.ancestor(
        of: activeLine,
        matching: find.byType(ImageFiltered),
      ).first,
    );
    expect(blur.imageFilter, isNotNull);
  });

  testWidgets('lyrics visual effects and inactive blur follow preferences', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.setLyricsOptions(
      glow: true,
      bloom: true,
      softLight: true,
      inactiveBlur: 3.0,
    );

    final document = LyricsDocument(
      providerId: 'test',
      providerName: 'Test',
      synced: true,
      lines: const [
        LyricsLine(0, 'Active line'),
        LyricsLine(10000, 'Inactive line'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsViewport(
            document: document,
            position: const Duration(seconds: 5),
            results: const {},
            providers: const [],
            onSeek: (_) {},
            onChooseProvider: () {},
            onToggleTranslation: () {},
            onRetry: () {},
            translationEnabled: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final activeText = tester.widget<Text>(find.text('Active line'));
    expect(activeText.style?.shadows, isNotEmpty);
    expect(activeText.style?.color, const Color(0xFFF5F0FF));

    final inactiveText = find.text('Inactive line');
    final inactiveFilter = tester.widget<ImageFiltered>(
      find.ancestor(of: inactiveText, matching: find.byType(ImageFiltered)).first,
    );
    final blur = inactiveFilter.imageFilter as ImageFilter;
    expect(blur.sigmaX, 3.0);
    expect(blur.sigmaY, 3.0);

    await settings.setLyricsOptions(
      glow: false,
      bloom: false,
      softLight: false,
      inactiveBlur: 1.7,
    );
  });

  testWidgets('provider and translation controls share one pill', (tester) async {
    var providerTaps = 0;
    var translationTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricsTranslationControlPill(
              translationEnabled: false,
              onChooseProvider: () => providerTaps++,
              onToggleTranslation: () => translationTaps++,
            ),
          ),
        ),
      ),
    );

    final providerControl = find.byTooltip('Choose lyrics provider');
    final translationControl =
        find.byTooltip('Enable translation / romanization');
    expect(providerControl, findsOneWidget);
    expect(translationControl, findsOneWidget);

    await tester.tap(providerControl);
    await tester.pump();
    await tester.tap(translationControl);
    await tester.pump();

    expect(providerTaps, 1);
    expect(translationTaps, 1);
    expect(
      find.ancestor(
        of: providerControl,
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: translationControl,
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
  });
}
