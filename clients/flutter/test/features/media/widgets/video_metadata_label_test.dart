import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/network/server_api.dart';
import 'package:pocketlink_client/features/media/widgets/video_metadata_label.dart';

void main() {
  testWidgets('renders available resolution and formatted duration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoMetadataLabel(
          future: Future.value(const VideoMetadata(
            durationMs: 125000,
            width: 1920,
            height: 1080,
          )),
          formatDuration: (milliseconds) => '2:05',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('1920×1080 · 2:05'), findsOneWidget);
  });

  testWidgets('renders nothing when metadata is unavailable', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoMetadataLabel(
          future: Future.value(null),
          formatDuration: (milliseconds) => '0:00',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('1920×1080 · 2:05'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
