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

  test('applies vertical morph drags one-to-one and clamps progress', () {
    expect(
      PocketLinkNavigation.updateMorphProgress(
        current: 1,
        dragDelta: 120,
        extent: 800,
      ),
      closeTo(0.85, 0.0001),
    );
    expect(
      PocketLinkNavigation.updateMorphProgress(
        current: 0.5,
        dragDelta: -200,
        extent: 800,
      ),
      closeTo(0.75, 0.0001),
    );
    expect(
      PocketLinkNavigation.updateMorphProgress(
        current: 0.1,
        dragDelta: 300,
        extent: 800,
      ),
      0,
    );
    expect(
      PocketLinkNavigation.updateMorphProgress(
        current: 0.9,
        dragDelta: -300,
        extent: 800,
      ),
      1,
    );
  });

  test('uses distance and velocity thresholds for morph release', () {
    expect(
      PocketLinkNavigation.shouldCollapseNowPlaying(
        progress: 0.75,
        downwardVelocity: 0,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldCollapseNowPlaying(
        progress: 0.9,
        downwardVelocity: 700,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldCollapseNowPlaying(
        progress: 0.9,
        downwardVelocity: 100,
      ),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.25,
        upwardVelocity: 0,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.1,
        upwardVelocity: -700,
      ),
      isTrue,
    );
  });
}
