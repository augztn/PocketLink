import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/now_playing_scroll_dismiss_detector.dart';

void main() {
  Widget buildSubject({
    required VoidCallback onDismiss,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NowPlayingScrollDismissDetector(
          onDismissDragStart: () {},
          onDismissDragUpdate: (_) {},
          onDismissDragEnd: (_) => onDismiss(),
          child: SizedBox(
            height: 300,
            child: SingleChildScrollView(
              child: SizedBox(height: 700, child: const Text('Scrollable content')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('downward swipe at scroll origin dismisses Now Playing', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(buildSubject(onDismiss: () => dismissals++));

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 160));
    await tester.pump();

    expect(dismissals, 1);
  });

  testWidgets('downward swipe while content is scrolled preserves scrolling', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(buildSubject(onDismiss: () => dismissals++));

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));

    final offsetBefore = scrollable.position.pixels;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();

    expect(dismissals, 0);
    expect(scrollable.position.pixels, lessThan(offsetBefore));
  });

  testWidgets('gesture setting disables scroll dismissal', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingScrollDismissDetector(
            enabled: false,
            onDismissDragStart: () {},
            onDismissDragUpdate: (_) {},
            onDismissDragEnd: (_) => dismissals++,
            child: const SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: SizedBox(height: 700),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 180));
    await tester.pump();

    expect(dismissals, 0);
  });

  testWidgets('horizontal swipe does not dismiss Now Playing', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(buildSubject(onDismiss: () => dismissals++));

    await tester.drag(find.byType(SingleChildScrollView), const Offset(180, 0));
    await tester.pump();

    expect(dismissals, 0);
  });
}
