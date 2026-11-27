import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/global_mini_player_bar.dart';
import 'package:pocketlink_client/features/media/persistent_audio_player.dart';

void main() {
  const item = MediaQueueItem(
    title: 'A long song title.mp3',
    path: '/music/song.mp3',
    artist: 'Anirudh Ravichander',
  );

  Future<void> pumpMiniPlayer(
    WidgetTester tester, {
    bool isPlaying = true,
    bool canSkip = true,
    bool visible = true,
    VoidCallback? onOpen,
    VoidCallback? onDismiss,
    VoidCallback? onTogglePlayback,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    Duration position = const Duration(seconds: 30),
    Duration duration = const Duration(seconds: 60),
    VoidCallback? onExpandDragStart,
    ValueChanged<double>? onExpandDragUpdate,
    ValueChanged<double>? onExpandDragEnd,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlobalMiniPlayerBar(
              item: item,
              visible: visible,
              surfaceIntensity: visible ? 1.0 : 0.0,
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
              onExpandDragStart: onExpandDragStart,
              onExpandDragUpdate: onExpandDragUpdate,
              onExpandDragEnd: onExpandDragEnd,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows track, transport controls and playback progress', (tester) async {
    await pumpMiniPlayer(tester);

    expect(find.text('A long song title.mp3'), findsOneWidget);
    expect(find.text('Anirudh Ravichander'), findsOneWidget);
    expect(find.text('NOW PLAYING · SWIPE TO SKIP'), findsNothing);
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
      tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Previous track',
        ),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Next track',
        ),
      ).onPressed,
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

  testWidgets('upward swipe on mini-player requests Now Playing expansion', (tester) async {
    final dragDeltas = <double>[];
    double? releaseVelocity;
    await pumpMiniPlayer(
      tester,
      onExpandDragUpdate: dragDeltas.add,
      onExpandDragEnd: (velocity) => releaseVelocity = velocity,
    );

    await tester.fling(
      find.byType(GlobalMiniPlayerBar),
      const Offset(0, -140),
      1000,
    );
    await tester.pump();

    expect(dragDeltas, isNotEmpty);
    expect(dragDeltas.any((delta) => delta < 0), isTrue);
    expect(releaseVelocity, isNotNull);
    expect(releaseVelocity, lessThan(0));
  });

  testWidgets('hidden mini-player keeps its active drag recognizer hit-testable',
      (tester) async {
    final dragDeltas = <double>[];
    double? releaseVelocity;
    await pumpMiniPlayer(
      tester,
      visible: false,
      onExpandDragStart: () {},
      onExpandDragUpdate: dragDeltas.add,
      onExpandDragEnd: (velocity) => releaseVelocity = velocity,
    );

    await tester.fling(
      find.byType(GlobalMiniPlayerBar),
      const Offset(0, -140),
      1000,
    );
    await tester.pump();

    expect(dragDeltas, isNotEmpty);
    expect(dragDeltas.any((delta) => delta < 0), isTrue);
    expect(releaseVelocity, isNotNull);
    expect(releaseVelocity, lessThan(0));
  });

  testWidgets('vertical drag start is reported before expansion begins', (tester) async {
    var started = 0;
    await pumpMiniPlayer(
      tester,
      onExpandDragStart: () => started++,
      onExpandDragUpdate: (_) {},
      onExpandDragEnd: (_) {},
    );

    await tester.fling(
      find.byType(GlobalMiniPlayerBar),
      const Offset(0, -100),
      700,
    );
    await tester.pump();

    expect(started, 1);
  });

  testWidgets('vertical drag cancellation settles the morph gesture', (tester) async {
    double? releaseVelocity;
    await pumpMiniPlayer(
      tester,
      onExpandDragUpdate: (_) {},
      onExpandDragEnd: (velocity) => releaseVelocity = velocity,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlobalMiniPlayerBar)),
    );
    await gesture.moveBy(const Offset(0, -48));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(releaseVelocity, 0);
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
