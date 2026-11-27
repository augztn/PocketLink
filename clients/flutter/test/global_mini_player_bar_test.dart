import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/global_mini_player_bar.dart';
import 'package:pocketlink_client/features/media/persistent_audio_player.dart';

void main() {
  const surfaceKey = ValueKey('mini-player-surface');
  const item = MediaQueueItem(
    title: 'Test track',
    artist: 'Test artist',
    path: '/Music/test-track.mp3',
  );

  Widget buildPlayer({
    required VoidCallback onOpen,
    required VoidCallback onExpandStart,
    required ValueChanged<double> onExpandUpdate,
    required ValueChanged<double> onExpandEnd,
    required VoidCallback onNext,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: GlobalMiniPlayerBar(
              item: item,
              visible: true,
              reduceMotion: true,
              isPlaying: true,
              position: Duration.zero,
              duration: const Duration(minutes: 3),
              canSkipPrevious: true,
              canSkipNext: true,
              onOpen: onOpen,
              onDismiss: () {},
              onTogglePlayback: () {},
              onSkipPrevious: () {},
              onSkipNext: onNext,
              surfaceKey: surfaceKey,
              onExpandDragStart: onExpandStart,
              onExpandDragUpdate: onExpandUpdate,
              onExpandDragEnd: onExpandEnd,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('upward mini-player swipe starts and updates expansion', (tester) async {
    var started = false;
    final deltas = <double>[];
    double? endVelocity;

    await tester.pumpWidget(buildPlayer(
      onOpen: () {},
      onExpandStart: () => started = true,
      onExpandUpdate: deltas.add,
      onExpandEnd: (value) => endVelocity = value,
      onNext: () {},
    ));

    await tester.drag(find.byKey(surfaceKey), const Offset(0, -140));
    await tester.pumpAndSettle();

    expect(started, isTrue);
    expect(deltas, isNotEmpty);
    expect(deltas.reduce((a, b) => a + b), lessThan(0));
    expect(endVelocity, isNotNull);
  });

  testWidgets('horizontal mini-player swipe still skips next', (tester) async {
    var nextCount = 0;

    await tester.pumpWidget(buildPlayer(
      onOpen: () {},
      onExpandStart: () {},
      onExpandUpdate: (_) {},
      onExpandEnd: (_) {},
      onNext: () => nextCount++,
    ));

    await tester.drag(find.byKey(surfaceKey), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(nextCount, 1);
  });
}
