import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/storage_volume_tile.dart';

void main() {
  testWidgets('renders volume details and direct-access icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StorageVolumeTile(
          title: 'USB drive',
          value: 'Direct access · read and write',
          selected: false,
          onTap: null,
          accessType: 'direct',
        ),
      ),
    ));

    expect(find.text('USB drive'), findsOneWidget);
    expect(find.text('Direct access · read and write'), findsOneWidget);
    expect(find.byIcon(Icons.sd_storage_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows selected state and forwards selection tap', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StorageVolumeTile(
          title: 'Portable storage',
          value: 'Folder permission saved · ready to use',
          selected: true,
          onTap: () => tapCount++,
          accessType: 'saf',
        ),
      ),
    ));

    expect(find.byIcon(Icons.usb_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Portable storage'), findsOneWidget);
    await tester.tap(find.text('Portable storage'));
    expect(tapCount, 1);
  });
}
