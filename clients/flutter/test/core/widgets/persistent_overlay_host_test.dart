import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/widgets/persistent_overlay_host.dart';

void main() {
  testWidgets('keeps OverlayPortal mounted and updates its child', (tester) async {
    final controller = OverlayPortalController();
    Widget portal(String label) => OverlayPortal(
          controller: controller,
          overlayChildBuilder: (_) => const Text('overlay child'),
          child: Text(label),
        );

    await tester.pumpWidget(PersistentOverlayHost(child: portal('first')));
    controller.show();
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('overlay child'), findsOneWidget);

    await tester.pumpWidget(PersistentOverlayHost(child: portal('second')));
    await tester.pump();

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('overlay child'), findsOneWidget);
  });
}
