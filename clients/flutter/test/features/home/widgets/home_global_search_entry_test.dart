import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/home/widgets/home_global_search_entry.dart';

void main() {
  BoxDecoration decoration(ThemeData theme, {double radius = 18}) =>
      BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
      );

  testWidgets('renders search label and forwards tap callback', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeGlobalSearchEntry(
          cardDecoration: decoration,
          onTap: () => tapCount++,
        ),
      ),
    ));

    expect(find.text('Search files, folders and media'), findsOneWidget);
    await tester.tap(find.text('Search files, folders and media'));
    expect(tapCount, 1);
  });
}
