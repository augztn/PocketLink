import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';
import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/features/home/navigation_dock.dart';
import 'package:pocketlink_client/core/widgets/liquid_glass_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await AppSettings.instance.setUseLiquidGlass(false);
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

  testWidgets('3+1 dock uses shared safe-area gutters and flexes at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            padding: EdgeInsets.only(left: 10, right: 20, bottom: 24),
          ),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: FloatingNavigationDock(
              order: const ['home', 'explore', 'files', 'browse'],
              visibleItems: const {'home', 'explore', 'files', 'browse'},
              selectedIndex: 0,
              onSelect: (_) {},
              onBrowsePressed: () {},
            ),
          ),
        ),
      ),
    );

    final capsule = tester.getRect(find.byType(LiquidGlassPill).first);
    final music = tester.getRect(find.byKey(PocketLinkNavigation.musicButtonKey));
    expect(capsule.left, 26);
    expect(music.right, 324);
    expect(music.left - capsule.right, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active glass lens tracks every measured tab slot', (tester) async {
    await AppSettings.instance.setUseLiquidGlass(true);

    for (final tabCount in [2, 3]) {
      final ids = ['home', 'explore', 'files'].take(tabCount).toList();
      final controller = PageController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: controller,
              children: List<Widget>.generate(
                tabCount,
                (index) => Center(child: Text('Page $index')),
              ),
            ),
            bottomNavigationBar: FloatingNavigationDock(
              order: [...ids, 'browse'],
              visibleItems: {...ids, 'browse'},
              selectedIndex: 0,
              pageController: controller,
              pageIndices: {
                for (var index = 0; index < tabCount; index++) index: index,
              },
              onSelect: (index) => controller.jumpToPage(index),
              onBrowsePressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final capsule = tester.getRect(find.byType(LiquidGlassPill).first);
      final innerLeft = capsule.left + 5;
      final innerWidth = capsule.width - 10;
      final tabWidth = innerWidth / tabCount;

      for (var index = 0; index < tabCount; index++) {
        controller.jumpToPage(index);
        await tester.pump();
        final lens = tester.getRect(
          find.byKey(const ValueKey<String>('navigation-active-lens')),
        );
        expect(
          lens.center.dx,
          closeTo(innerLeft + tabWidth * (index + 0.5), 1.5),
          reason: 'lens should be centered in tab $index of $tabCount',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      controller.dispose();
    }
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
