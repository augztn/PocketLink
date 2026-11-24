import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink/features/media/music_library_screen.dart';

void main() {
  testWidgets('Library Bento card displays collection count and handles taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 150,
          child: LibraryBentoCard(
            title: 'Songs',
            count: 42,
            icon: Icons.music_note_rounded,
            art: LibraryBentoArt.album,
            onTap: () => tapped = true,
          ),
        ),
      ),
    ));

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    await tester.tap(find.text('Songs'));
    expect(tapped, isTrue);
  });

  testWidgets('Empty Library Bento card uses its category watermark', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 150,
          child: LibraryBentoCard(
            title: 'Albums',
            count: 0,
            icon: Icons.album_rounded,
            art: LibraryBentoArt.album,
            onTap: () {},
          ),
        ),
      ),
    ));

    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.album_rounded), findsOneWidget);
  });
}
