import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/widgets/video_grid_card.dart';

void main() {
  testWidgets('renders video details and forwards open and favourite actions', (tester) async {
    var openCalls = 0;
    var favouriteCalls = 0;
    var downloadCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: VideoGridCard(
              title: 'Sample video.mp4',
              extension: 'MP4',
              sizeLabel: '24 MB',
              favorite: false,
              artwork: const ColoredBox(color: Colors.black),
              durationBadge: const Text('02:30'),
              metadataLabel: const Text('1080p · 02:30'),
              onOpen: () => openCalls++,
              onDownload: () async => downloadCalls++,
              onToggleFavorite: () => favouriteCalls++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sample video.mp4'), findsOneWidget);
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('24 MB'), findsOneWidget);
    expect(find.text('1080p · 02:30'), findsOneWidget);

    await tester.tap(find.text('Sample video.mp4'));
    await tester.tap(find.byTooltip('Add favourite'));

    expect(openCalls, 1);
    expect(favouriteCalls, 1);
    expect(downloadCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
