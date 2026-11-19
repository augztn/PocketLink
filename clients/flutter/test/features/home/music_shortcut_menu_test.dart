import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/features/home/music_shortcut_menu.dart';

void main() {
  testWidgets('Music button menu shows all default destinations', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: MusicShortcutMenu(
                shortcuts: const [
                  'photos', 'music', 'videos', 'documents',
                  'files', 'search', 'drives',
                ],
                expanded: true,
                onSelect: (id) => selected = id,
              ),
            ),
          ),
        ),
      ),
    );

    for (final label in [
      'Photos', 'Music', 'Videos', 'Documents', 'Files', 'Search', 'Drives',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    final drivesTile = find.ancestor(of: find.text('Drives'), matching: find.byType(InkWell));
    final photosTile = find.ancestor(of: find.text('Photos'), matching: find.byType(InkWell));
    expect(tester.getSize(drivesTile).width, greaterThan(tester.getSize(photosTile).width));
    await tester.tap(find.text('Drives'));
    expect(selected, 'drives');
  });
}
