import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/now_playing_scrubber.dart';

void main() {
  test('the fixed player scrubber uses the Apple capsule style', () {
    expect(NowPlayingScrubberStyle.appleCapsule.key, 'apple');
  });

  testWidgets('unknown duration shows safe placeholder timestamps',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingScrubber(
            style: NowPlayingScrubberStyle.appleCapsule,
            position: Duration.zero,
            duration: Duration.zero,
            bufferedPosition: Duration.zero,
            isPlaying: false,
            isBuffering: true,
            onSeek: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scrubber painter variants remain renderable internally',
      (tester) async {
    for (final style in NowPlayingScrubberStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NowPlayingScrubberPreview(style: style),
          ),
        ),
      );
      final preview = find.byType(NowPlayingScrubberPreview);
      expect(preview, findsOneWidget);
      expect(
        find.descendant(of: preview, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
    }
  });
}
