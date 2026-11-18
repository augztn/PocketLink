import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/features/home/floating_quick_shortcut.dart';

void main() {
  testWidgets('single tap opens the primary pinned shortcut', (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FloatingQuickShortcut(
                shortcuts: const ['explore', 'music'],
                expanded: false,
                useLiquidGlass: false,
                onTap: () => opened = true,
                onLongPress: () {},
                longPressEnabled: true,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Explore · Hold for shortcuts'), findsOneWidget);
    await tester.tap(find.byTooltip('Explore · Hold for shortcuts'));
    expect(opened, isTrue);
  });

  testWidgets(
    'long press expands pinned destinations and selection is routed',
    (tester) async {
      String? selected;
      var expanded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MediaQuery(
                    data: const MediaQueryData(disableAnimations: true),
                    child: FloatingQuickShortcut(
                      shortcuts: const ['explore', 'music', 'photos'],
                      expanded: expanded,
                      useLiquidGlass: false,
                      onTap: () {},
                      onLongPress: () => setState(() => expanded = true),
                      longPressEnabled: true,
                      onSelect: (id) => selected = id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        MediaQuery.disableAnimationsOf(
          tester.element(find.byType(FloatingQuickShortcut)),
        ),
        isTrue,
      );

      await tester.longPress(find.byTooltip('Explore · Hold for shortcuts'));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);

      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);

      await tester.tap(find.text('Music'));
      expect(selected, 'music');
    },
  );

  testWidgets('long press can be disabled without affecting single tap', (tester) async {
    var opened = false;
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingQuickShortcut(
            shortcuts: const ['explore', 'music'],
            expanded: false,
            useLiquidGlass: false,
            onTap: () => opened = true,
            onLongPress: () => expanded = true,
            longPressEnabled: false,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Explore'), findsOneWidget);
    await tester.longPress(find.byTooltip('Explore'));
    expect(expanded, isFalse);

    await tester.tap(find.byTooltip('Explore'));
    expect(opened, isTrue);
  });
  testWidgets('menu-only mode shows Search and Drives for the Music button', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: FloatingQuickShortcut(
                shortcuts: const ['photos', 'music', 'videos', 'documents', 'files', 'search', 'drives'],
                expanded: true,
                useLiquidGlass: false,
                onTap: () {},
                onLongPress: () {},
                longPressEnabled: false,
                onSelect: (id) => selected = id,
                showButton: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Drives'), findsOneWidget);
    expect(find.byTooltip('Photos'), findsNothing);

    await tester.tap(find.text('Drives'));
    expect(selected, 'drives');
  });

}
