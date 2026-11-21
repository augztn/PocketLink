import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_media_metric.dart';

void main() {
  testWidgets('renders media count, label and matching icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HostMediaMetric(
          label: 'Photos',
          value: 24,
          icon: Icons.photo_outlined,
        ),
      ),
    ));

    expect(find.text('24'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders non-numeric values using their string representation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HostMediaMetric(
          label: 'Status',
          value: 'Ready',
          icon: Icons.check_circle_outline,
        ),
      ),
    ));

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
  });
}
