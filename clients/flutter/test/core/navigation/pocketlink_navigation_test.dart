import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';

void main() {
  testWidgets('resolves mini-player and dock anchors in overlay coordinates',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            key: PocketLinkNavigation.mediaOverlayKey,
            children: [
              Positioned(
                left: 12,
                top: 34,
                child: SizedBox(
                  key: PocketLinkNavigation.miniPlayerAnchorKey,
                  width: 300,
                  height: 60,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 20,
                child: SizedBox(
                  key: PocketLinkNavigation.nowPlayingDockButtonKey,
                  width: 64,
                  height: 64,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final miniRect = PocketLinkNavigation.resolveMediaRect(
      PocketLinkNavigation.miniPlayerAnchorKey,
    );
    expect(miniRect, const Rect.fromLTWH(12, 34, 300, 60));
    final dockRect = PocketLinkNavigation.resolveMediaRect(
      PocketLinkNavigation.nowPlayingDockButtonKey,
    );
    expect(dockRect, isNotNull);
    expect(dockRect!.width, 64);
    expect(dockRect.height, 64);
    expect(dockRect.right, closeTo(tester.view.physicalSize.width /
        tester.view.devicePixelRatio - 10, 0.5));
  });

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

  test('nested Back handling is enabled only for the active tab', () {
    expect(
      PocketLinkNavigation.shouldHandleNestedBack(
        isActive: true,
        canPop: true,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldHandleNestedBack(
        isActive: false,
        canPop: true,
      ),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldHandleNestedBack(
        isActive: true,
        canPop: false,
      ),
      isFalse,
    );
  });

  test('nested Back callbacks never dispatch from inactive tabs or player', () {
    expect(
      PocketLinkNavigation.shouldDispatchNestedBack(
        isActive: true,
        nowPlayingProgress: 0,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldDispatchNestedBack(
        isActive: false,
        nowPlayingProgress: 0,
      ),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldDispatchNestedBack(
        isActive: true,
        nowPlayingProgress: 0.01,
      ),
      isFalse,
    );
  });

  test('Back collapses Now Playing only when expanded past halfway', () {
    expect(
      PocketLinkNavigation.shouldCollapseNowPlayingOnBack(progress: 0.5),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldCollapseNowPlayingOnBack(progress: 0.5001),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldCollapseNowPlayingOnBack(progress: 1),
      isTrue,
    );
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
        progress: 0.749,
        downwardVelocity: 0,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldCollapseNowPlaying(
        progress: 0.9,
        downwardVelocity: 281,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldCollapseNowPlaying(
        progress: 0.75,
        downwardVelocity: 280,
      ),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.18,
        upwardVelocity: 0,
      ),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.2,
        upwardVelocity: 0,
      ),
      isFalse,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.2001,
        upwardVelocity: 0,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.07,
        upwardVelocity: -251,
      ),
      isTrue,
    );
    expect(
      PocketLinkNavigation.shouldExpandFromMiniPlayer(
        progress: 0.07,
        upwardVelocity: -250,
      ),
      isFalse,
    );
  });
}
