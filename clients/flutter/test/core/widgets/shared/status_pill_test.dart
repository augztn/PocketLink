import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/core/widgets/shared/status_pill.dart';

void main() {
  testWidgets('renders the supplied status label, icon and surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PocketLinkStatusPill(
              label: 'Connected',
              foreground: Colors.green,
              background: Color(0x2210B981),
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              radius: 20,
              textStyle: TextStyle(color: Colors.green, fontSize: 11),
              icon: Icons.check_circle_rounded,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    final surface = tester.widget<Container>(
      find.ancestor(
        of: find.text('Connected'),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0x2210B981));
    expect(decoration.borderRadius, BorderRadius.circular(20));
  });
}
