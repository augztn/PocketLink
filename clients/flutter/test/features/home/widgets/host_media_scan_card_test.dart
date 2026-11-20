import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/features/home/widgets/host_media_scan_card.dart';

void main() {
  Widget buildSubject({
    bool serverOnline = false,
    String? scanError,
    VoidCallback onStartScan = _noop,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: HostMediaScanCard(
          status: null,
          scanError: scanError,
          savingSettings: false,
          startingScan: false,
          serverOnline: serverOnline,
          checking: false,
          volumes: const [],
          cardDecoration: const BoxDecoration(),
          formatTimestamp: (timestamp, {timezoneOffsetMinutes}) =>
              timestamp <= 0 ? 'Not yet scanned' : 'Scanned',
          formatInterval: (minutes) => '$minutes min',
          formatBytes: (bytes) => '$bytes B',
          onShowHistory: (_) {},
          onShowSkippedItems: (_) {},
          onUpdateAutomaticScanning: ({
            required enabled,
            required intervalMinutes,
            required scanOnStartup,
            required scanOnStorageChange,
          }) {},
          onStartScan: onStartScan,
          onRetryScan: _noop,
          onShareReport: (_) {},
        ),
      ),
    );
  }

  testWidgets('shows the initial host media library state', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Host media library'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(
      find.text('Refresh the host device media and file index remotely.'),
      findsOneWidget,
    );
    expect(find.text('Scan host now'), findsOneWidget);
  });

  testWidgets('shows scan errors without changing the card structure', (tester) async {
    await tester.pumpWidget(
      buildSubject(scanError: 'Host media index is unavailable.'),
    );

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Host media index is unavailable.'), findsOneWidget);
  });

  testWidgets('forwards the manual scan action when the host is online', (tester) async {
    var started = false;
    await tester.pumpWidget(
      buildSubject(
        serverOnline: true,
        onStartScan: () => started = true,
      ),
    );

    await tester.tap(find.text('Scan host now'));
    expect(started, isTrue);
  });
}

void _noop() {}
