import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/widgets/music_equalizer.dart';

void main() {
  testWidgets('renders four animated playback bars', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MusicEqualizer(),
      ),
    ));

    expect(find.byType(Container), findsNWidgets(4));

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Container), findsNWidgets(4));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
