import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';
import 'package:pocketlink_client/features/home/navigation_dock.dart';

void main() {
  testWidgets('Music button supports tap, hold and horizontal swipe callbacks',
      (tester) async {
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

    await tester.longPress(find.byKey(PocketLinkNavigation.musicButtonKey));
    expect(holds, 1);

    final button = find.byIcon(Icons.music_note_rounded);
    final nextGesture = await tester.startGesture(tester.getCenter(button));
    await nextGesture.moveBy(const Offset(-54, 0));
    await tester.pump();
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    await nextGesture.up();
    await tester.pumpAndSettle();
    expect(next, 1);

        final previousGesture = await tester.startGesture(
      tester.getCenter(find.byKey(PocketLinkNavigation.musicButtonKey)),
    );
    await previousGesture.moveBy(const Offset(54, 0));
    await tester.pump();
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    await previousGesture.up();
    await tester.pumpAndSettle();
    expect(previous, 1);
  });
}
