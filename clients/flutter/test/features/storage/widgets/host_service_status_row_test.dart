import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_service_status_row.dart';

void main() {
  testWidgets('renders ready status with success indicator', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HostServiceStatusRow(
          label: 'Storage service',
          value: 'Running',
          ready: true,
        ),
      ),
    ));

    expect(find.text('Storage service'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders neutral and warning states distinctly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            HostServiceStatusRow(
              label: 'Stopped service',
              value: 'Stopped',
              ready: false,
              neutral: true,
            ),
            HostServiceStatusRow(
              label: 'Storage permission',
              value: 'Needs access',
              ready: false,
            ),
          ],
        ),
      ),
    ));

    expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(find.text('Stopped service'), findsOneWidget);
    expect(find.text('Storage permission'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
