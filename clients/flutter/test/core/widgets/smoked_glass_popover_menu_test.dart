import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/widgets/smoked_glass_popover_menu.dart';

void main() {
  testWidgets('popover blooms from its trigger and returns the selected action', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SmokedGlassPopoverMenu<String>(
                tooltip: 'More actions',
                items: const [
                  SmokedGlassPopoverMenuItem(
                    value: 'rename',
                    label: 'Rename',
                    icon: Icons.drive_file_rename_outline_rounded,
                  ),
                  SmokedGlassPopoverMenuItem(
                    value: 'delete',
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                  ),
                ],
                onSelected: (value) => selected = value,
                child: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    final menuCard = find.ancestor(
      of: find.text('Rename'),
      matching: find.byType(ConstrainedBox),
    ).first;
    final menuWidth = tester.getSize(menuCard).width;
    expect(menuWidth, greaterThanOrEqualTo(210));
    expect(menuWidth, lessThanOrEqualTo(236));
    final menuRow = find.ancestor(
      of: find.text('Rename'),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 44,
      ),
    ).first;
    expect(tester.getSize(menuRow).height, 44);

    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(selected, 'rename');
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('system back dismisses only the popover route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('Music library'),
              SmokedGlassPopoverMenu<String>(
                items: const [
                  SmokedGlassPopoverMenuItem(
                    value: 'folders',
                    label: 'Folders',
                    icon: Icons.folder_rounded,
                  ),
                ],
                onSelected: (_) {},
                child: const Text('Music view'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Music view'));
    await tester.pumpAndSettle();
    expect(find.text('Folders'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Folders'), findsNothing);
    expect(find.text('Music library'), findsOneWidget);
  });

  testWidgets('outside tap dismisses the popover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SmokedGlassPopoverMenu<String>(
                items: const [
                  SmokedGlassPopoverMenuItem(
                    value: 'refresh',
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                  ),
                ],
                onSelected: (_) {},
                child: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tapAt(const Offset(24, 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('Refresh'), findsNothing);
  });
}
