import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_repository.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_viewport.dart';

void main() {
  testWidgets('provider and translation controls share one pill', (tester) async {
    var providerTaps = 0;
    var translationTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsViewport(
            document: const LyricsDocument(
              providerId: 'lrclib',
              providerName: 'LRCLIB',
              lines: [LyricsLine(0, 'Test lyric line')],
              synced: false,
            ),
            position: Duration.zero,
            results: const {},
            providers: const [],
            onSeek: (_) {},
            onChooseProvider: () => providerTaps++,
            onToggleTranslation: () => translationTaps++,
            onRetry: () {},
            translationEnabled: false,
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
  });
}
