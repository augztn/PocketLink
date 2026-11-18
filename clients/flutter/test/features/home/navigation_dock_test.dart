import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/features/home/navigation_dock.dart';

void main() {
  testWidgets('Music button supports tap, hold and horizontal swipe callbacks', (tester) async {
    var taps = 0;
    var holds = 0;
    var next = 0;
    var previous = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingNavigationDock(
            order: const ['home', 'browse', 'explore', 'files'],
            visibleItems: const {'home', 'browse', 'explore', 'files'},
            selectedIndex: 0,
            onSelect: (_) {},
            onBrowsePressed: () => taps++,
            onMusicShortcutLongPress: () => holds++,
            onBrowseSwipeLeft: () => next++,
            onBrowseSwipeRight: () => previous++,
          ),
        ),
      ),
    );

    final musicButton = find.byIcon(Icons.music_note_rounded);
    expect(musicButton, findsOneWidget);

    await tester.tap(musicButton);
    expect(taps, 1);

    await tester.longPress(musicButton);
    expect(holds, 1);

    await tester.fling(musicButton, const Offset(-100, 0), 900);
    await tester.pumpAndSettle();
    expect(next, 1);

    await tester.fling(musicButton, const Offset(100, 0), 900);
    await tester.pumpAndSettle();
    expect(previous, 1);
  });
}
