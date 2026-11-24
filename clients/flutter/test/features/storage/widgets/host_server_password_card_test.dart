import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_server_password_card.dart';

void main() {
  testWidgets('shows password guidance and saves through its callback', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var saveCalls = 0;
    var visibilityToggles = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostServerPasswordCard(
          controller: controller,
          configured: false,
          busy: false,
          obscurePassword: true,
          onToggleVisibility: () => visibilityToggles++,
          onSave: () => saveCalls++,
        ),
      ),
    ));

    expect(find.text('Native server password'), findsOneWidget);
    expect(find.text('Choose a password with at least 12 characters.'), findsOneWidget);
    expect(find.text('Save password'), findsOneWidget);
    final passwordField = tester.widget<TextField>(find.byType(TextField));
    expect(passwordField.obscureText, isTrue);
    expect(passwordField.scrollPadding, const EdgeInsets.only(bottom: 120));
    expect(passwordField.textInputAction, TextInputAction.done);

    await tester.tap(find.byTooltip('Show password'));
    await tester.tap(find.text('Save password'));
    expect(visibilityToggles, 1);
    expect(saveCalls, 1);

    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(saveCalls, 2);
  });

  testWidgets('shows configured state and disables editing while busy', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostServerPasswordCard(
          controller: controller,
          configured: true,
          busy: true,
          obscurePassword: true,
          onToggleVisibility: () {},
          onSave: () {},
        ),
      ),
    ));

    expect(find.text('Configured'), findsOneWidget);
    expect(find.text('Update password'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
