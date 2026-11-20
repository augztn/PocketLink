import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/widgets/video_tag.dart';

void main() {
  testWidgets('renders the supplied video duration label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: VideoTag(label: '1:42'),
      ),
    ));

    expect(find.text('1:42'), findsOneWidget);
  });
}
