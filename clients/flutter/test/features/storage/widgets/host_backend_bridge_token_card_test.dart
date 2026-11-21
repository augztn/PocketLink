import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/storage/widgets/host_backend_bridge_token_card.dart';

void main() {
  testWidgets('shows a masked token and delegates visibility and copy actions', (tester) async {
    var visibilityCalls = 0;
    var copyCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostBackendBridgeTokenCard(
          token: 'bridge-secret-token',
          statusLoaded: true,
          obscureToken: true,
          onToggleVisibility: () => visibilityCalls++,
          onCopy: () => copyCalls++,
        ),
      ),
    ));

    expect(find.text('Backend bridge token'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('••••••••••••••••••••••••'), findsOneWidget);
    expect(find.text('bridge-secret-token'), findsNothing);

    await tester.tap(find.byTooltip('Show bridge token'));
    await tester.tap(find.byTooltip('Copy bridge token'));
    expect(visibilityCalls, 1);
    expect(copyCalls, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostBackendBridgeTokenCard(
          token: 'bridge-secret-token',
          statusLoaded: true,
          obscureToken: false,
          onToggleVisibility: () {},
          onCopy: () {},
        ),
      ),
    ));
    expect(find.text('bridge-secret-token'), findsOneWidget);
  });

  testWidgets('distinguishes loading from unavailable token states', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostBackendBridgeTokenCard(
          token: null,
          statusLoaded: false,
          obscureToken: true,
          onToggleVisibility: () {},
          onCopy: () {},
        ),
      ),
    ));

    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Loading bridge token…'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostBackendBridgeTokenCard(
          token: null,
          statusLoaded: true,
          obscureToken: true,
          onToggleVisibility: () {},
          onCopy: () {},
        ),
      ),
    ));

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsOneWidget);
  });
}
