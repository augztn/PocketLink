import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/features/home/widgets/host_device_metrics_card.dart';

void main() {
  Widget buildSubject({
    required bool serverOnline,
    String? telemetryError,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: HostDeviceMetricsCard(
          telemetry: null,
          telemetryError: telemetryError,
          serverOnline: serverOnline,
          volumes: const [],
          cardDecoration: const BoxDecoration(),
          formatBytes: (bytes) => '$bytes B',
        ),
      ),
    );
  }

  testWidgets('shows connection guidance while the host is offline', (tester) async {
    await tester.pumpWidget(buildSubject(serverOnline: false));

    expect(find.text('HOST DEVICE HEALTH'), findsOneWidget);
    expect(
      find.text('System information appears when the host is connected.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the telemetry error while the host is online', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        serverOnline: true,
        telemetryError: 'Could not read host device health.',
      ),
    );

    expect(find.text('Could not read host device health.'), findsOneWidget);
  });
}
