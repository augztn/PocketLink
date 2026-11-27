import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/files/files_home_content.dart';

void main() {
  testWidgets('Files home respects pinned header and floating overlay clearance',
      (tester) async {
    await tester.view.setPhysicalSize(const Size(432, 960));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FilesHomeContent(
            volumes: [],
            recent: [],
            favorites: [],
            lastPath: '',
            lastVolume: null,
            topInset: 104,
            bottomInset: 190,
            onOpenInternal: _noop,
            onOpenDownloads: _noop,
            onOpenVolume: _noopString,
            onOpenRecent: _noopRecent,
            onOpenFavorite: _noopRecent,
            onOpenLastLocation: _noop,
            onBrowseCategory: _noopString,
          ),
        ),
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.padding, const EdgeInsets.fromLTRB(18, 104, 18, 190));
    expect(find.text('Your files'), findsNothing);
    expect(find.text('Browse storage and pick up where you left off.'), findsNothing);
    expect(find.text('Browse by type'), findsOneWidget);

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.padding, EdgeInsets.zero);

    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
  });
}

void _noop() {}
void _noopString(String value) {}
void _noopRecent(dynamic value) {}
