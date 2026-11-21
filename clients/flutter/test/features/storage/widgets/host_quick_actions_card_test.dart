import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_quick_actions_card.dart';

void main() {
  testWidgets('renders all actions and delegates each callback', (tester) async {
    var storageCalls = 0;
    var securityCalls = 0;
    var diagnosticsCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostQuickActionsCard(
          onManageStorage: () => storageCalls++,
          onSecuritySettings: () => securityCalls++,
          onDiagnostics: () => diagnosticsCalls++,
        ),
      ),
    ));

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Jump directly to the controls you need.'), findsOneWidget);

    await tester.tap(find.text('Manage storage'));
    await tester.tap(find.text('Security settings'));
    await tester.tap(find.text('Diagnostics'));

    expect(storageCalls, 1);
    expect(securityCalls, 1);
    expect(diagnosticsCalls, 1);
  });
}
