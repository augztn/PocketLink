import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/global_mini_player_bar.dart';
import 'package:pocketlink_client/features/media/persistent_audio_player.dart';

void main() {
  const item = MediaQueueItem(
    title: 'A long song title.mp3',
    path: '/music/song.mp3',
  );

  Future<void> pumpMiniPlayer(
    WidgetTester tester, {
    bool isPlaying = true,
    bool canSkip = true,
    VoidCallback? onOpen,
    VoidCallback? onDismiss,
    VoidCallback? onTogglePlayback,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    Duration position = const Duration(seconds: 30),
    Duration duration = const Duration(seconds: 60),
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlobalMiniPlayerBar(
              item: item,
              visible: true,
              reduceMotion: true,
              isPlaying: isPlaying,
              position: position,
              duration: duration,
              canSkipPrevious: canSkip,
              canSkipNext: canSkip,
              onOpen: onOpen ?? () {},
              onDismiss: onDismiss ?? () {},
              onTogglePlayback: onTogglePlayback ?? () {},
              onSkipPrevious: onPrevious ?? () {},
              onSkipNext: onNext ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows track, transport controls and playback progress', (tester) async {
    await pumpMiniPlayer(tester);

    expect(find.text('A long song title.mp3'), findsOneWidget);
    expect(find.text('NOW PLAYING · SWIPE TO SKIP'), findsOneWidget);
    expect(find.byTooltip('Previous track'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Next track'), findsOneWidget);

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.5);
  });

  testWidgets('transport controls invoke the matching callbacks', (tester) async {
    var previous = 0;
    var toggled = 0;
    var next = 0;
    await pumpMiniPlayer(
      tester,
      onPrevious: () => previous++,
      onTogglePlayback: () => toggled++,
      onNext: () => next++,
    );

    await tester.tap(find.byTooltip('Previous track'));
    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Next track'));

    expect(previous, 1);
    expect(toggled, 1);
    expect(next, 1);
  });

  testWidgets('horizontal swipes skip tracks in the matching direction', (tester) async {
    var previous = 0;
    var next = 0;
    await pumpMiniPlayer(
      tester,
      onPrevious: () => previous++,
      onNext: () => next++,
    );

    final bar = find.byType(GlobalMiniPlayerBar);
    await tester.fling(bar, const Offset(-120, 0), 1000);
    await tester.pump();
    await tester.fling(bar, const Offset(120, 0), 1000);
    await tester.pump();

    expect(next, 1);
    expect(previous, 1);
  });

  testWidgets('does not skip when the queue has only one track', (tester) async {
    var previous = 0;
    var next = 0;
    await pumpMiniPlayer(
      tester,
      canSkip: false,
      onPrevious: () => previous++,
      onNext: () => next++,
    );

    expect(
      tester.widget<IconButton>(find.byTooltip('Previous track')).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byTooltip('Next track')).onPressed,
      isNull,
    );

    await tester.fling(
      find.byType(GlobalMiniPlayerBar),
      const Offset(-120, 0),
      1000,
    );
    await tester.pump();

    expect(previous, 0);
    expect(next, 0);
  });

  testWidgets('paused mini-player can be dismissed with a downward swipe only', (tester) async {
    var dismissed = 0;
    await pumpMiniPlayer(
      tester,
      isPlaying: false,
      onDismiss: () => dismissed++,
    );

    await tester.fling(
      find.byType(GlobalMiniPlayerBar),
      const Offset(0, 100),
      1000,
    );
    await tester.pump();

    expect(dismissed, 1);
    expect(find.text('PAUSED'), findsOneWidget);
  });

  testWidgets('zero duration renders an empty progress indicator', (tester) async {
    await pumpMiniPlayer(
      tester,
      position: Duration.zero,
      duration: Duration.zero,
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0);
  });
}
