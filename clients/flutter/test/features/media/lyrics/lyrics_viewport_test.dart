import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_viewport.dart';

void main() {
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
