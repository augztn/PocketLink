import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_external_storage_section.dart';

void main() {
  testWidgets('shows empty-drive guidance and delegates refresh and folder selection', (tester) async {
    var refreshCalls = 0;
    var folderCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HostExternalStorageSection(
            volumes: const [],
            selectedVolumeCount: 0,
            detectedVolumeCount: 0,
            busy: false,
            refreshing: false,
            onRefresh: () => refreshCalls++,
            onChooseFolder: () => folderCalls++,
            onSelectVolume: (_) {},
          ),
        ),
      ),
    ));

    expect(find.text('USB / External Storage'), findsOneWidget);
    expect(find.text('No removable drive detected'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh connected storage'));
    await tester.tap(find.text('Choose storage folder'));

    expect(refreshCalls, 1);
    expect(folderCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders detected volumes and delegates volume and folder actions', (tester) async {
    var selectedVolumeId = '';
    var folderCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HostExternalStorageSection(
            volumes: const [
              {
                'id': 'usb-one',
                'name': 'USB drive',
                'access': 'direct',
                'writable': true,
                'selected': false,
              },
            ],
            selectedVolumeCount: 0,
            detectedVolumeCount: 1,
            busy: false,
            refreshing: false,
            onRefresh: () {},
            onChooseFolder: () => folderCalls++,
            onSelectVolume: (id) => selectedVolumeId = id,
          ),
        ),
      ),
    ));

    expect(find.text('1 drive(s) detected · approve access to use'), findsOneWidget);
    expect(find.text('Direct access · read and write'), findsOneWidget);

    await tester.tap(find.text('USB drive'));
    await tester.tap(find.text('Choose a folder manually'));

    expect(selectedVolumeId, 'usb-one');
    expect(folderCalls, 1);
  });

  testWidgets('disables refresh and storage actions while busy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HostExternalStorageSection(
            volumes: const [],
            selectedVolumeCount: 0,
            detectedVolumeCount: 0,
            busy: true,
            refreshing: false,
            onRefresh: () {},
            onChooseFolder: () {},
            onSelectVolume: (_) {},
          ),
        ),
      ),
    ));

    expect(tester.widget<IconButton>(find.byTooltip('Refresh connected storage')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Choose storage folder')).onPressed, isNull);
  });
}
