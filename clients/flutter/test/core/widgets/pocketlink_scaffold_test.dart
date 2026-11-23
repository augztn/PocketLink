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
    expect(insets.bottomClearance, 192);
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

    expect(insets.bottomClearance, 46);
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

    expect(insets.bottomClearance, 120);
  });

  testWidgets('keeps header clearance stable and isolated per route', (tester) async {
    final routeA = Object();
    final routeB = Object();
    final routeC = Object();
    final activeRoutes = <Object>[routeA, routeB, routeC];
    final firstRowKey = GlobalKey();

    Future<double> mountRoute(Object route, double headerHeight) async {
      late double topClearance;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: 24, bottom: 34),
            ),
            child: PocketLinkScaffold(
              routeIdentity: route,
              activeRouteIdentities: activeRoutes,
              hasFloatingNavBar: false,
              hasActiveMiniPlayer: false,
              child: Builder(
                builder: (context) {
                  LayoutInsetsScope.reportRenderedHeader(
                    context,
                    route,
                    headerHeight,
                  );
                  topClearance = LayoutInsetsScope.of(context).topClearance;
                  return SizedBox(
                    height: topClearance,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        key: firstRowKey,
                        height: 20,
                        child: const Text('First row'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getTopLeft(find.byKey(firstRowKey)).dy;
    }

    for (final entry in <(Object, double)>[
      (routeA, 104),
      (routeB, 128),
      (routeC, 116),
    ]) {
      final initialTop = await mountRoute(entry.$1, entry.$2);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(find.byKey(firstRowKey)).dy,
          initialTop,
          reason: 'First-row position changed while idle on a route',
        );
      }
    }

    // Returning to an existing route reuses its own measurement.
    final routeATop = await mountRoute(routeA, 104);
    expect(routeATop, 24);
  });
}
