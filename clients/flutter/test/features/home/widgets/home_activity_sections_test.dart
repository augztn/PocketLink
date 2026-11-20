import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/home/widgets/home_activity_sections.dart';
import 'package:pocketlink_client/core/storage/home_activity_store.dart';

void main() {
  BoxDecoration decoration(ThemeData theme, {double radius = 18}) => BoxDecoration(
    color: theme.colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(radius),
  );

  testWidgets('Continue section shows its empty state and browse action', (tester) async {
    var browseCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeContinueSection(
          items: const [],
          cardDecoration: decoration,
          onBrowseMedia: () => browseCount++,
          onSelectItem: (_) {},
        ),
      ),
    ));

    expect(find.text('Your recent tracks, folders and files will appear here.'), findsOneWidget);
    await tester.tap(find.text('Browse media'));
    expect(browseCount, 1);
  });

  testWidgets('Recent files section shows loading and error states', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeRecentFilesSection(
          files: const [],
          error: null,
          checking: true,
          cardDecoration: decoration,
          formatBytes: (bytes) => '$bytes B',
          relativeTime: (_) => 'Just now',
          iconForFile: (_) => Icons.insert_drive_file_outlined,
          onBrowse: () {},
          onFileTap: (_) {},
          onAction: (_, __) {},
        ),
      ),
    ));

    expect(find.text('Checking your folders for recent files…'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeRecentFilesSection(
          files: const [],
          error: 'Recent files unavailable.',
          checking: false,
          cardDecoration: decoration,
          formatBytes: (bytes) => '$bytes B',
          relativeTime: (_) => 'Just now',
          iconForFile: (_) => Icons.insert_drive_file_outlined,
          onBrowse: () {},
          onFileTap: (_) {},
          onAction: (_, __) {},
        ),
      ),
    ));
    expect(find.text('Recent files unavailable.'), findsOneWidget);
  });

  testWidgets('Continue section forwards selected activity', (tester) async {
    final item = HomeActivityItem(
      kind: 'folder',
      title: 'Movies',
      path: '/Movies',
      serverUrl: 'http://localhost:8000',
      updatedAt: DateTime(2026),
    );
    HomeActivityItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeContinueSection(
          items: [item],
          cardDecoration: decoration,
          onBrowseMedia: () {},
          onSelectItem: (value) => selected = value,
        ),
      ),
    ));

    await tester.tap(find.text('Movies'));
    expect(selected, same(item));
  });
}
