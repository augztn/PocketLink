import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_viewport.dart';
import 'package:pocketlink_client/features/media/now_playing_lyrics_mode.dart';

void main() {
  testWidgets('compact lyrics header aligns artwork and actions to 24dp', (tester) async {
    await tester.view.setPhysicalSize(const Size(432, 900));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: NowPlayingLyricsMode(
              progress: 1,
              background: const ColoredBox(color: Colors.black),
              artwork: const ColoredBox(color: Colors.orange),
              trackTitle: 'Param Sundari',
              artistLabel: 'Shreya Ghoshal',
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 38, height: 38),
                  const SizedBox(width: 10),
                  const SizedBox(width: 38, height: 38),
                ],
              ),
              onClose: () {},
              lyricsContent: const ColoredBox(color: Colors.black),
              providerLabel: 'Lyrics by LRCLIB',
              onChooseProvider: () {},
              translationControl: LyricsTranslationControlPill(
                translationEnabled: false,
                onChooseProvider: () {},
                onToggleTranslation: () {},
              ),
              footer: const SizedBox(height: 292),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final artwork = tester.getTopLeft(
      find.byKey(const ValueKey('lyrics-mode-artwork')),
    );
    expect(artwork.dx, 24);
    expect(artwork.dy, 24.5);

    final handle = tester.getSize(
      find.byKey(const ValueKey('lyrics-mode-grab-handle')),
    );
    expect(handle.width, 40);
    expect(handle.height, 4.5);

    final header = tester.getTopLeft(
      find.byKey(const ValueKey('lyrics-mode-compact-header')),
    );
    expect(header.dx, 0);
    expect(tester.getSize(
      find.byKey(const ValueKey('lyrics-mode-compact-header')),
    ).width, 432);
    expect(header.dy, 24.5);

    final footer = find.byKey(
      const ValueKey('lyrics-mode-attribution-footer'),
    );
    expect(find.text('Lyrics by LRCLIB'), findsOneWidget);
    expect(find.byType(LyricsTranslationControlPill), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Lyrics by LRCLIB'),
        matching: footer,
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(LyricsTranslationControlPill),
        matching: footer,
      ),
      findsOneWidget,
    );

    final viewportBottom = tester.getBottomLeft(
      find.byKey(const ValueKey('lyrics-mode-lyrics-viewport')),
    ).dy;
    final footerTop = tester.getTopLeft(footer).dy;
    expect(viewportBottom, lessThanOrEqualTo(footerTop));
  });
}
