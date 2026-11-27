import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink/core/widgets/persistent_overlay_host.dart';

void main() {
  testWidgets('keeps OverlayPortal mounted and updates its child', (tester) async {
    Widget portal(String label) => OverlayPortal(
          overlayChildBuilder: (_) => const SizedBox.shrink(),
          child: Text(label),
        );

    await tester.pumpWidget(PersistentOverlayHost(child: portal('first')));
    expect(find.text('first'), findsOneWidget);

    await tester.pumpWidget(PersistentOverlayHost(child: portal('second')));
    await tester.pump();

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });
}
