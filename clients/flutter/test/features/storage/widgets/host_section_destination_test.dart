import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_section_destination.dart';

void main() {
  testWidgets('renders selected destination with selected icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            HostSectionDestination(
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard_rounded,
              label: 'Overview',
              selected: true,
              onTap: _noop,
            ),
          ],
        ),
      ),
    ));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forwards taps for an unselected destination', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            HostSectionDestination(
              icon: Icons.devices_outlined,
              selectedIcon: Icons.devices_rounded,
              label: 'Device',
              selected: false,
              onTap: () => tapCount++,
            ),
          ],
        ),
      ),
    ));

    expect(find.byIcon(Icons.devices_outlined), findsOneWidget);
    await tester.tap(find.text('Device'));
    expect(tapCount, 1);
  });
}

void _noop() {}
