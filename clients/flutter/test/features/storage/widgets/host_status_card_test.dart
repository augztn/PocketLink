import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_status_card.dart';

void main() {
  testWidgets('shows checking state while host status is loading', (tester) async {
    var refreshCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostStatusCard(
          statusLoaded: false,
          running: false,
          apiRunning: false,
          serverPasswordConfigured: false,
          bridgeRunning: false,
          internalGranted: false,
          usbStatus: 'Not connected',
          selectedVolumeCount: 0,
          detectedVolumeCount: 0,
          refreshing: false,
          busy: false,
          statusCheckedLabel: 'Status has not been checked yet',
          onRefresh: () => refreshCalls++,
        ),
      ),
    ));

    expect(find.text('Host status'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Storage service'), findsNothing);
    await tester.tap(find.byTooltip('Refresh host status'));
    expect(refreshCalls, 1);
  });

  testWidgets('renders service, API, bridge and storage states', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HostStatusCard(
          statusLoaded: true,
          running: true,
          apiRunning: true,
          serverPasswordConfigured: true,
          bridgeRunning: false,
          internalGranted: true,
          usbStatus: '2 ready',
          selectedVolumeCount: 2,
          detectedVolumeCount: 2,
          refreshing: false,
          busy: false,
          statusCheckedLabel: 'Updated 21/11 · 6:30 AM',
          onRefresh: _noop,
        ),
      ),
    ));

    expect(find.text('Storage service'), findsOneWidget);
    expect(find.text('Native server API'), findsOneWidget);
    expect(find.text('Android storage bridge'), findsOneWidget);
    expect(find.text('Internal storage'), findsOneWidget);
    expect(find.text('USB / external drives'), findsOneWidget);
    expect(find.text('2 ready'), findsOneWidget);
    expect(find.text('Updated 21/11 · 6:30 AM'), findsOneWidget);
    expect(find.text('Running'), findsNWidgets(3));
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets('shows password setup state and disables refresh when busy', (tester) async {
    var refreshCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostStatusCard(
          statusLoaded: true,
          running: false,
          apiRunning: false,
          serverPasswordConfigured: false,
          bridgeRunning: false,
          internalGranted: false,
          usbStatus: 'Not connected',
          selectedVolumeCount: 0,
          detectedVolumeCount: 0,
          refreshing: false,
          busy: true,
          statusCheckedLabel: 'Updated just now',
          onRefresh: () => refreshCalls++,
        ),
      ),
    ));

    expect(find.text('Password not set'), findsOneWidget);
    expect(tester.widget<IconButton>(
      find.byTooltip('Refresh host status'),
    ).onPressed, isNull);
    await tester.tap(find.byTooltip('Refresh host status'));
    expect(refreshCalls, 0);
  });

  testWidgets('shows progress indicator while refreshing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HostStatusCard(
          statusLoaded: true,
          running: false,
          apiRunning: false,
          serverPasswordConfigured: true,
          bridgeRunning: false,
          internalGranted: false,
          usbStatus: 'Not connected',
          selectedVolumeCount: 0,
          detectedVolumeCount: 0,
          refreshing: true,
          busy: false,
          statusCheckedLabel: 'Updated just now',
          onRefresh: _noop,
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

void _noop() {}
