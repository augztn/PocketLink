import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/home/widgets/home_active_transfers_preview.dart';
import 'package:pocketlink_client/features/transfers/transfer_manager.dart';

void main() {
  BoxDecoration decoration(ThemeData theme, {double radius = 18}) =>
      BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
      );

  TransferTask task({
    String name = 'photo.jpg',
    String direction = 'Upload',
    int transferred = 50,
    int total = 100,
  }) =>
      TransferTask(
        id: 'task-1',
        name: name,
        direction: direction,
        location: '/Photos',
        startedAt: DateTime(2026),
        cancelToken: CancelToken(),
        operation: (_, __) async {},
        transferred: transferred,
        total: total,
      );

  testWidgets('renders active transfer progress and opens transfer manager',
      (tester) async {
    var openCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeActiveTransfersPreview(
          tasks: [task()],
          formatBytes: (bytes) => '$bytes B',
          cardDecoration: decoration,
          onOpen: () => openCount++,
        ),
      ),
    ));

    expect(find.text('Active transfers'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('50 B of 100 B'), findsOneWidget);
    await tester.tap(find.text('View all'));
    expect(openCount, 1);
  });

  testWidgets('renders no card when there are no active transfers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeActiveTransfersPreview(
          tasks: const [],
          formatBytes: (bytes) => '$bytes B',
          cardDecoration: decoration,
          onOpen: () {},
        ),
      ),
    ));

    expect(find.text('Active transfers'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
