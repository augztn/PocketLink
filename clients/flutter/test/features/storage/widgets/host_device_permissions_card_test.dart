import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_device_permissions_card.dart';

void main() {
  testWidgets('shows loading state and disables permission actions', (tester) async {
    var internalCalls = 0;
    var backgroundCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostDevicePermissionsCard(
          statusLoaded: false,
          requiredAccessReady: false,
          internalGranted: false,
          backgroundGranted: false,
          busy: false,
          refreshingStatus: false,
          onRequestInternalStorageAccess: () => internalCalls++,
          onRequestBackgroundAccess: () => backgroundCalls++,
          onRefresh: () {},
        ),
      ),
    ));

    expect(find.text('Device permissions'), findsOneWidget);
    expect(find.text('Checking Android access…'), findsOneWidget);
    expect(find.text('Checking'), findsNWidgets(3));
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNotNull);

    await tester.tap(find.text('All-files access'));
    await tester.tap(find.text('Background activity'));
    expect(internalCalls, 0);
    expect(backgroundCalls, 0);
  });

  testWidgets('shows granted and recommended states and delegates actions', (tester) async {
    var internalCalls = 0;
    var backgroundCalls = 0;
    var refreshCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostDevicePermissionsCard(
          statusLoaded: true,
          requiredAccessReady: true,
          internalGranted: true,
          backgroundGranted: false,
          busy: false,
          refreshingStatus: false,
          onRequestInternalStorageAccess: () => internalCalls++,
          onRequestBackgroundAccess: () => backgroundCalls++,
          onRefresh: () => refreshCalls++,
        ),
      ),
    ));

    expect(find.text('Required access is ready'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);

    await tester.tap(find.text('All-files access'));
    await tester.tap(find.text('Background activity'));
    await tester.tap(find.text('Refresh permission status'));

    expect(internalCalls, 0);
    expect(backgroundCalls, 1);
    expect(refreshCalls, 1);
  });

  testWidgets('disables refresh while busy or refreshing', (tester) async {
    Future<void> pumpCard({
      required bool busy,
      required bool refreshingStatus,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HostDevicePermissionsCard(
            statusLoaded: true,
            requiredAccessReady: false,
            internalGranted: false,
            backgroundGranted: false,
            busy: busy,
            refreshingStatus: refreshingStatus,
            onRequestInternalStorageAccess: () {},
            onRequestBackgroundAccess: () {},
            onRefresh: () {},
          ),
        ),
      ));
    }

    await pumpCard(busy: true, refreshingStatus: false);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);

    await pumpCard(busy: false, refreshingStatus: true);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(find.text('Checking permissions…'), findsOneWidget);
  });
}
