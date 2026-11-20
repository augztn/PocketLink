import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_storage_service_card.dart';

void main() {
  testWidgets('shows running state and delegates stop action', (tester) async {
    var stopCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostStorageServiceCard(
          running: true,
          canStart: true,
          busy: false,
          onStart: () {},
          onStop: () => stopCalls++,
        ),
      ),
    ));

    expect(find.text('Storage service'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('PocketLink storage access is running on this phone.'), findsOneWidget);
    expect(find.text('Stop storage service'), findsOneWidget);

    await tester.tap(find.text('Stop storage service'));
    expect(stopCalls, 1);
  });

  testWidgets('shows readiness guidance and disables start without access', (tester) async {
    var startCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostStorageServiceCard(
          running: false,
          canStart: false,
          busy: false,
          onStart: () => startCalls++,
          onStop: () {},
        ),
      ),
    ));

    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Complete a storage permission above before starting.'), findsOneWidget);
    expect(find.text('Enable All-files access or grant access to a USB folder to continue.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(startCalls, 0);
  });

  testWidgets('enables start when access is ready and disables while busy', (tester) async {
    var startCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostStorageServiceCard(
          running: false,
          canStart: true,
          busy: false,
          onStart: () => startCalls++,
          onStop: () {},
        ),
      ),
    ));

    expect(find.text('Your storage setup is ready. Start the service when needed.'), findsOneWidget);
    await tester.tap(find.text('Start storage service'));
    expect(startCalls, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostStorageServiceCard(
          running: false,
          canStart: true,
          busy: true,
          onStart: () => startCalls++,
          onStop: () {},
        ),
      ),
    ));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
