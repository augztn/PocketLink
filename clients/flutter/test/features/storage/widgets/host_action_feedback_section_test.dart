import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_action_feedback_section.dart';

void main() {
  testWidgets('shows progress while an action is busy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostActionFeedbackSection(busy: true, error: null),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the supplied error message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostActionFeedbackSection(
            busy: false,
            error: 'Could not save storage permission.',
          ),
        ),
      ),
    );

    expect(find.text('Could not save storage permission.'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('renders only spacing when idle without an error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostActionFeedbackSection(busy: false, error: null),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });
}
