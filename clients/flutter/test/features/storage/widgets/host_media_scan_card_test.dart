import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_media_scan_card.dart';

void main() {
  testWidgets('shows indexed counts and last completed time', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostMediaScanCard(
          status: const {'state': 'complete', 'photo_count': 12, 'video_count': 3, 'music_count': 8, 'file_count': 21, 'scanned': 44},
          scanning: false,
          skippedItems: 0,
          completedAt: '20/11/2026 · 10:30 AM',
          busy: false,
          onScan: () {},
        ),
      ),
    ));

    expect(find.text('Media and files indexed'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Last completed: 20/11/2026 · 10:30 AM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows scan errors and disables scan action while scanning', (tester) async {
    var scanCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostMediaScanCard(
          status: const {'state': 'scanning', 'last_error': 'Temporary read error'},
          scanning: true,
          skippedItems: 2,
          completedAt: null,
          busy: false,
          onScan: () => scanCalls++,
        ),
      ),
    ));

    expect(find.text('Temporary read error'), findsOneWidget);
    expect(find.text('2 items skipped'), findsOneWidget);
    await tester.tap(find.text('Scanning…'));
    expect(scanCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts a manual scan when idle', (tester) async {
    var scanCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostMediaScanCard(
          status: const {'state': 'ready'},
          scanning: false,
          skippedItems: 0,
          completedAt: null,
          busy: false,
          onScan: () => scanCalls++,
        ),
      ),
    ));

    await tester.tap(find.text('Scan media & files now'));
    expect(scanCalls, 1);
  });
}
