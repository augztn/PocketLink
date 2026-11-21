import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_device_intro_card.dart';

void main() {
  testWidgets('shows host introduction and setup description', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HostDeviceIntroCard()),
      ),
    );

    expect(find.text('Host PocketLink on this device'), findsOneWidget);
    expect(
      find.text(
        'Manage this phone’s host service, Android storage bridge and access readiness.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.phonelink_setup_rounded), findsOneWidget);
  });
}
