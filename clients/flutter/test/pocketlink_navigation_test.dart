import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';

void main() {
  group('PocketLinkNavigationObserver', () {
    late PocketLinkNavigationObserver observer;

    setUp(() {
      observer = PocketLinkNavigationObserver();
    });

    tearDown(() {
      observer.routeStack.dispose();
    });

    test('tracks the active route and restores the previous route on pop', () {
      final dashboard = MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: PocketLinkRouteNames.dashboard,
        ),
        builder: (_) => const SizedBox.shrink(),
      );
      final mediaBrowser = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      final nowPlaying = MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: PocketLinkRouteNames.nowPlaying,
        ),
        builder: (_) => const SizedBox.shrink(),
      );

      observer.didPush(dashboard, null);
      expect(observer.isDashboardVisible, isTrue);
      expect(observer.isNowPlayingVisible, isFalse);

      observer.didPush(mediaBrowser, dashboard);
      expect(observer.isDashboardVisible, isFalse);

      observer.didPush(nowPlaying, mediaBrowser);
      expect(observer.isNowPlayingVisible, isTrue);

      observer.didPop(nowPlaying, mediaBrowser);
      expect(observer.isNowPlayingVisible, isFalse);
      expect(observer.currentPageRoute, same(mediaBrowser));
    });

    test('updates the active route after replacement and removal', () {
      final dashboard = MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: PocketLinkRouteNames.dashboard,
        ),
        builder: (_) => const SizedBox.shrink(),
      );
      final nowPlaying = MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: PocketLinkRouteNames.nowPlaying,
        ),
        builder: (_) => const SizedBox.shrink(),
      );

      observer.didPush(dashboard, null);
      observer.didReplace(newRoute: nowPlaying, oldRoute: dashboard);
      expect(observer.isNowPlayingVisible, isTrue);

      observer.didRemove(nowPlaying, null);
      expect(observer.currentPageRoute, isNull);
      expect(observer.isNowPlayingVisible, isFalse);
    });
    test('opens Now Playing after a single swipe crosses 20 percent', () {
      expect(
        PocketLinkNavigation.shouldExpandFromMiniPlayer(
          progress: 0.21,
          upwardVelocity: -100,
        ),
        isTrue,
      );
    });

    test('opens Now Playing from a short fast upward swipe', () {
      expect(
        PocketLinkNavigation.shouldExpandFromMiniPlayer(
          progress: 0,
          upwardVelocity: -251,
        ),
        isTrue,
      );
    });

    test('does not expand from a small slow accidental movement', () {
      expect(
        PocketLinkNavigation.shouldExpandFromMiniPlayer(
          progress: 0.04,
          upwardVelocity: -80,
        ),
        isFalse,
      );
    });

  });
}
