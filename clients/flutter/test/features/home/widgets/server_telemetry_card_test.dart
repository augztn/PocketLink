import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/features/home/widgets/server_telemetry_card.dart';

void main() {
  Widget buildSubject({
    required bool serverOnline,
    bool checking = false,
    Duration? latency,
    String? serverName,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ServerTelemetryCard(
          apiBaseUrl: 'http://100.64.0.1:8000',
          serverName: serverName,
          routeLabel: 'Tailscale',
          checking: checking,
          serverOnline: serverOnline,
          latency: latency,
          lastCheckedAt: null,
          volumes: const [],
          volumeError: null,
          onShowServerSwitcher: () {},
          onQuickUpload: () {},
          onRefresh: () {},
          onReturnToConnection: () {},
          onOpenFiles: () {},
        ),
      ),
    );
  }

  testWidgets('shows offline state and reconnect guidance', (tester) async {
    await tester.pumpWidget(buildSubject(serverOnline: false));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == 'Offline',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Server is unreachable. Check the network or server service.'),
      findsOneWidget,
    );
    expect(find.text('Tailscale'), findsOneWidget);
  });

  testWidgets('shows the configured server name and measured latency', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        serverOnline: true,
        latency: const Duration(milliseconds: 123),
        serverName: 'PocketLink server',
      ),
    );

    expect(find.text('PocketLink server'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText().contains('Online'),
      ),
      findsOneWidget,
    );
    expect(find.text('123 ms'), findsWidgets);
  });
}
