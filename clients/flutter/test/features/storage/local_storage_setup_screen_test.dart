import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/features/storage/local_storage_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('homeserver/saf');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'status':
          return <String, Object?>{
            'running': false,
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

  testWidgets('Host navigation switches sections and keeps one layout', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LocalStorageSetupScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Host PocketLink on this device'), findsOneWidget);
    expect(find.text('Layout'), findsNothing);
    expect(find.text('Device permissions'), findsNothing);

    await tester.tap(find.text('Storage'));
    await tester.pumpAndSettle();
    expect(find.text('Device permissions'), findsOneWidget);
    expect(find.text('USB / External Storage'), findsOneWidget);

    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    expect(find.text('Native server password'), findsOneWidget);
    expect(find.text('Backend bridge token'), findsOneWidget);
    expect(find.text('test-token'), findsNothing);
    await tester.tap(find.byTooltip('Show bridge token'));
    await tester.pumpAndSettle();
    expect(find.text('test-token'), findsOneWidget);
    expect(find.text('Device permissions'), findsNothing);
  });
}
