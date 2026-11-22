import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/core/widgets/pocketlink_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('computes dock and mini-player clearance from mounted overlays', (tester) async {
    late LayoutInsetsScope insets;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: PocketLinkScaffold(
            hasFloatingNavBar: true,
            hasActiveMiniPlayer: true,
            child: Builder(
              builder: (context) {
                insets = LayoutInsetsScope.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(insets.topClearance, 90);
    expect(insets.bottomClearance, 216);
    expect(insets.hasFloatingNavBar, isTrue);
    expect(insets.hasActiveMiniPlayer, isTrue);
  });

  testWidgets('uses only safe margin when dock and mini-player are absent', (tester) async {
    late LayoutInsetsScope insets;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: PocketLinkScaffold(
            hasFloatingNavBar: false,
            hasActiveMiniPlayer: false,
            child: Builder(
              builder: (context) {
                insets = LayoutInsetsScope.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(insets.bottomClearance, 70);
  });

  testWidgets('reserves mini-player space without a floating dock', (tester) async {
    late LayoutInsetsScope insets;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: PocketLinkScaffold(
            hasFloatingNavBar: false,
            hasActiveMiniPlayer: true,
            child: Builder(
              builder: (context) {
                insets = LayoutInsetsScope.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(insets.bottomClearance, 144);
  });

  testWidgets('horizontal gutter includes the 16dp base and system safe insets', (tester) async {
    late EdgeInsets gutter;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(left: 10, right: 20),
          ),
          child: Builder(
            builder: (context) {
              gutter = PocketLinkHorizontalGutter.padding(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(gutter, const EdgeInsets.fromLTRB(26, 0, 36, 0));
  });

  testWidgets('updates top clearance from the rendered header measurement', (tester) async {
    late LayoutInsetsScope insets;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: PocketLinkScaffold(
            hasFloatingNavBar: false,
            hasActiveMiniPlayer: false,
            child: Builder(
              builder: (context) {
                LayoutInsetsScope.reportRenderedHeader(context, 104);
                insets = LayoutInsetsScope.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(insets.topClearance, 98);
  });
}
