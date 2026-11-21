import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/home/widgets/home_quick_actions_section.dart';

void main() {
  BoxDecoration decoration(ThemeData theme, {double radius = 18}) =>
      BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
      );

  testWidgets('quick actions forwards edit and selection callbacks',
      (tester) async {
    var editCount = 0;
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeQuickActionsSection(
          actions: const [
            HomeQuickAction(
              id: 'files',
              label: 'Files',
              icon: Icons.folder_open_rounded,
            ),
            HomeQuickAction(
              id: 'music',
              label: 'Music',
              icon: Icons.headphones_rounded,
            ),
          ],
          cardDecoration: decoration,
          onEdit: () => editCount++,
          onSelect: (id) => selected = id,
        ),
      ),
    ));

    expect(find.text('Quick actions'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    expect(editCount, 1);
    await tester.tap(find.text('Music'));
    expect(selected, 'music');
  });

  testWidgets('empty quick actions offers the add action', (tester) async {
    var editCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeQuickActionsSection(
          actions: const [],
          cardDecoration: decoration,
          onEdit: () => editCount++,
          onSelect: (_) {},
        ),
      ),
    ));

    expect(find.text('Add quick actions'), findsOneWidget);
    await tester.tap(find.text('Add quick actions'));
    expect(editCount, 1);
  });
}
