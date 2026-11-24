import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';
import 'package:pocketlink_client/features/home/navigation_dock.dart';
import 'package:pocketlink_client/features/media/now_playing_overlay_controller.dart';

void main() {
  testWidgets(
    'three navigation tabs are centered in equal slots with one active lens',
    (tester) async {
      for (var activeIndex = 0; activeIndex < 3; activeIndex++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: FloatingNavigationDock(
                order: const ['home', 'explore', 'files'],
                visibleItems: const {'home', 'explore', 'files'},
                selectedIndex: activeIndex,
                onSelect: (_) {},
                onBrowsePressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final capsule = tester.getRect(
          find.byKey(const ValueKey('navigation-dock-tabs-capsule')),
        );
        final lens = tester.getRect(
          find.byKey(const ValueKey('navigation-dock-active-lens')),
        );
        expect(find.byType(BackdropFilter), findsOneWidget);

        final innerWidth = capsule.width - 10;
        final slotWidth = innerWidth / 3;
        final expectedCenter =
            capsule.left + 5 + (activeIndex + 0.5) * slotWidth;
        final activeLabel = tester.getCenter(
          find.text(['Home', 'Explore', 'Files'][activeIndex]),
        );

        expect(activeLabel.dx, closeTo(expectedCenter, 0.5));
        expect(lens.center.dx, closeTo(expectedCenter, 0.5));
        expect(lens.width, closeTo(slotWidth, 0.5));
        expect(
          find.byKey(const ValueKey('navigation-dock-active-lens')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('navigation-dock-tabs-capsule')),
            matching: find.byType(AnimatedContainer),
          ),
          findsNothing,
        );
      }
    },
  );

  testWidgets(
    'navigation dock follows the shared Now Playing expansion progress',
    (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 380),
      );
      NowPlayingOverlayController.expandProgress = controller;
      var selections = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingNavigationDock(
              order: const ['home', 'explore', 'files'],
              visibleItems: const {'home', 'explore', 'files'},
              selectedIndex: 0,
              onSelect: (_) => selections++,
              onBrowsePressed: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final capsule = find.byKey(
        const ValueKey('navigation-dock-tabs-capsule'),
      );
      final dockedTop = tester.getTopLeft(capsule).dy;

      controller.value = 0.45;
      await tester.pump();
      final hiddenTop = tester.getTopLeft(capsule).dy;
      expect(hiddenTop - dockedTop, closeTo(82, 0.5));

      await tester.tap(find.text('Explore'), warnIfMissed: false);
      expect(selections, 0);

      controller.value = 0;
      await tester.pump();
      expect(tester.getTopLeft(capsule).dy, closeTo(dockedTop, 0.5));

      NowPlayingOverlayController.expandProgress = null;
      controller.dispose();
    },
  );

  testWidgets('Discover search keeps Music button and mini-player dock lane while hiding tabs', (tester) async {
    PocketLinkNavigation.discoverSearchVisible.value = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: FloatingNavigationDock(
          order: const ['home', 'browse', 'explore', 'files'],
          visibleItems: const {'home', 'browse', 'explore', 'files'},
          selectedIndex: 1,
          onSelect: (_) {},
          onBrowsePressed: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('navigation-dock-tabs-capsule')), findsNothing);
    expect(find.byKey(PocketLinkNavigation.musicButtonKey), findsOneWidget);
    expect(tester.getCenter(find.byKey(PocketLinkNavigation.musicButtonKey)).dx,
        greaterThan(tester.getSize(find.byType(Scaffold)).width / 2));

    PocketLinkNavigation.discoverSearchVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-dock-tabs-capsule')), findsOneWidget);
  });

  testWidgets('expanded shortcuts dismiss from Music button without an X icon', (tester) async {
    var opens = 0;
    var dismisses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: FloatingNavigationDock(
          order: const ['home', 'browse', 'explore', 'files'],
          visibleItems: const {'home', 'browse', 'explore', 'files'},
          selectedIndex: 0,
          onSelect: (_) {},
          onBrowsePressed: () => opens++,
          musicShortcutsExpanded: true,
          onMusicShortcutDismissed: () => dismisses++,
        ),
      ),
    ));
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.tap(find.byKey(PocketLinkNavigation.musicButtonKey));
    expect(dismisses, 1);
    expect(opens, 0);
  });

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

    final button = find.byKey(PocketLinkNavigation.musicButtonKey);
    final nextGesture = await tester.startGesture(tester.getCenter(button));
    // Send several pointer updates so the horizontal drag recognizer can win
    // the gesture arena and deliver the full drag delta.
    for (var step = 0; step < 5; step++) {
      await nextGesture.moveBy(const Offset(-16, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    await nextGesture.up();
    await tester.pumpAndSettle();
    expect(next, 1);

    final previousGesture = await tester.startGesture(
      tester.getCenter(button),
    );
    for (var step = 0; step < 5; step++) {
      await previousGesture.moveBy(const Offset(16, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    await previousGesture.up();
    await tester.pumpAndSettle();
    expect(previous, 1);
  });
}
