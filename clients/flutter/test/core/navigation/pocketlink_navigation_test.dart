import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';

void main() {
  test('identifies only the welcome-screen standalone Discover route', () {
    final observer = PocketLinkNavigationObserver();
    final discoverRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(
        name: PocketLinkRouteNames.standaloneDiscover,
      ),
      builder: (_) => const SizedBox.shrink(),
    );

    observer.didPush(discoverRoute, null);
    expect(observer.isStandaloneDiscoverFlow, isTrue);

    final clientRoute = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );
    observer.didPush(clientRoute, discoverRoute);
    expect(observer.isStandaloneDiscoverFlow, isTrue);

    observer.didPop(clientRoute, discoverRoute);
    expect(observer.isStandaloneDiscoverFlow, isTrue);

    final dashboardRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: PocketLinkRouteNames.dashboard),
      builder: (_) => const SizedBox.shrink(),
    );
    observer.didPush(dashboardRoute, discoverRoute);
    expect(observer.isStandaloneDiscoverFlow, isFalse);

    observer.didPop(dashboardRoute, discoverRoute);
    expect(observer.isStandaloneDiscoverFlow, isTrue);

    observer.didPop(discoverRoute, null);
    expect(observer.isStandaloneDiscoverFlow, isFalse);
  });
}
