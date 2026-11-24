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

    expect(insets.topClearance, 94);
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
    final route = ValueNotifier<Object>(routeA);
    final firstRowKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: ValueListenableBuilder<Object>(
            valueListenable: route,
            builder: (context, currentRoute, _) => PocketLinkScaffold(
              routeIdentity: currentRoute,
              activeRouteIdentities: activeRoutes,
              hasFloatingNavBar: false,
              hasActiveMiniPlayer: false,
              child: Builder(
                builder: (context) {
                  final headerHeight = identical(currentRoute, routeA)
                      ? 104.0
                      : identical(currentRoute, routeB)
                          ? 128.0
                          : 116.0;
                  LayoutInsetsScope.reportRenderedHeader(
                    context,
                    currentRoute,
                    headerHeight,
                  );
                  final topClearance =
                      LayoutInsetsScope.of(context).topClearance;
                  return Padding(
                    padding: EdgeInsets.only(top: topClearance),
                    child: SizedBox(
                      key: firstRowKey,
                      height: 20,
                      child: const Text('First row'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> verifyStable(Object nextRoute, double expectedTop) async {
      route.value = nextRoute;
      await tester.pump();
      await tester.pump();
      final initialTop = tester.getTopLeft(find.byKey(firstRowKey)).dy;
      expect(initialTop, expectedTop);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(find.byKey(firstRowKey)).dy,
          initialTop,
          reason: 'First-row position changed while idle on a route',
        );
      }
    }

    await verifyStable(routeA, 106);
    await verifyStable(routeB, 130);
    await verifyStable(routeC, 118);
    await verifyStable(routeA, 106);
    route.dispose();
  });
}
