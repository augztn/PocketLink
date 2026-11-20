import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/widgets/media_info_row.dart';

void main() {
  testWidgets('renders label and value with the existing info-row layout', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MediaInfoRow('Codec', 'FLAC'),
      ),
    ));

    expect(find.text('Codec'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);
  });

  testWidgets('supports long values without overflowing the row', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          child: MediaInfoRow('Server path', '/Music/Albums/Long filename.flac'),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
