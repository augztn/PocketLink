import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeserver_client/features/home/floating_quick_shortcut.dart';

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
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    expect(opened, isTrue);
  });

  testWidgets(
    'long press expands pinned destinations and selection is routed',
    (tester) async {
      String? selected;
      var expanded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: FloatingQuickShortcut(
                      shortcuts: const ['explore', 'music', 'photos'],
                      expanded: expanded,
                      useLiquidGlass: false,
                      onTap: () {},
                      onLongPress: () => setState(() => expanded = true),
                      onSelect: (id) => selected = id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);

      await tester.tap(find.text('Music'));
      expect(selected, 'music');
    },
  );
}
