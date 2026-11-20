import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/storage/widgets/storage_permission_row.dart';

void main() {
  testWidgets('renders permission details and forwards tap', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StoragePermissionRow(
          icon: Icons.folder_open_rounded,
          title: 'All-files access',
          description: 'Direct access to shared storage',
          status: 'Enabled',
          granted: true,
          onTap: () => tapCount++,
        ),
      ),
    ));

    expect(find.text('All-files access'), findsOneWidget);
    expect(find.text('Direct access to shared storage'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    await tester.tap(find.text('All-files access'));
    expect(tapCount, 1);
  });

  testWidgets('does not show navigation affordance when action is unavailable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StoragePermissionRow(
          icon: Icons.usb_rounded,
          title: 'USB folder access',
          description: 'No drive connected',
          status: 'Not connected',
          granted: false,
          neutral: true,
          onTap: null,
        ),
      ),
    ));

    expect(find.text('USB folder access'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });
}
