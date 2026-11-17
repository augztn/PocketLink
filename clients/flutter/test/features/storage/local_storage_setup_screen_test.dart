import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/storage/local_storage_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pocketlink/saf');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'status':
          return <String, Object?>{
            'running': true,
            'apiRunning': true,
            'bridgeRunning': true,
            'internalStorageGranted': true,
            'backgroundAccessGranted': true,
            'serverPasswordConfigured': false,
            'discoveredVolumes': <Object?>[],
          };
        case 'token':
          return 'test-token';
        case 'mediaIndexStatus':
          return jsonEncode({'state': 'idle'});
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows detected removable storage and its access method', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'status':
          return <String, Object?>{
            'running': true,
            'apiRunning': true,
            'bridgeRunning': true,
            'internalStorageGranted': true,
            'backgroundAccessGranted': true,
            'serverPasswordConfigured': true,
            'discoveredVolumes': <Object?>[
              <String, Object?>{
                'id': 'usb-test-volume',
                'name': 'SD card',
                'selected': true,
                'access': 'direct',
                'writable': false,
                'state': 'mounted_ro',
              },
              <String, Object?>{
                'id': 'usb-second-volume',
                'name': 'USB drive',
                'selected': false,
                'access': 'not_granted',
                'writable': false,
                'state': 'mounted',
              },
            ],
          };
        case 'token':
          return 'test-token';
        case 'mediaIndexStatus':
          return jsonEncode({'state': 'idle'});
        default:
          return null;
      }
    });

    await tester.pumpWidget(
      const MaterialApp(home: LocalStorageSetupScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();

    final deviceList = find.byKey(
      const PageStorageKey<String>('host-storage'),
    );
    final deviceScrollable = find.descendant(
      of: deviceList,
      matching: find.byType(Scrollable),
    ).first;

    // ListView lazily builds off-screen volume tiles. Scroll each assertion
    // into view so the test verifies the rendered UI, not eager construction.
    await tester.scrollUntilVisible(
      find.text('SD card'),
      250,
      scrollable: deviceScrollable,
    );
    expect(find.text('SD card'), findsOneWidget);
    expect(find.text('Direct access · read-only'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('USB drive'),
      250,
      scrollable: deviceScrollable,
    );
    expect(find.text('USB drive'), findsOneWidget);
    expect(find.text('Detected · tap to approve folder access'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Choose a folder manually'),
      250,
      scrollable: deviceScrollable,
    );
    expect(find.text('Choose a folder manually'), findsOneWidget);
  });

  testWidgets('Host navigation switches sections and keeps one layout', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LocalStorageSetupScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Host PocketLink on this device'), findsOneWidget);
    expect(find.text('Host status'), findsOneWidget);
    expect(find.text('Android storage bridge'), findsOneWidget);
    expect(find.text('Manage storage'), findsOneWidget);
    expect(find.text('Security settings'), findsOneWidget);
    expect(find.byTooltip('Refresh host status'), findsOneWidget);
    expect(find.text('Layout'), findsNothing);
    expect(find.text('Device permissions'), findsNothing);
    expect(find.text('Storage'), findsNothing);

    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();
    expect(find.text('Device permissions'), findsOneWidget);
    expect(find.text('USB / External Storage'), findsOneWidget);

    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    expect(find.text('Native server password'), findsOneWidget);
    expect(find.text('Backend bridge token'), findsOneWidget);
    expect(find.text('test-token'), findsNothing);
    await tester.drag(
      find.byKey(const PageStorageKey<String>('host-security')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show bridge token'));
    await tester.pumpAndSettle();
    expect(find.text('test-token'), findsOneWidget);
    expect(find.text('Device permissions'), findsNothing);
  });
}
