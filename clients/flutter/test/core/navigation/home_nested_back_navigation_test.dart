import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/navigation/pocketlink_navigation.dart';

void main() {
  testWidgets('system Back pops Commute to Search, then Search to Discover', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _NestedBackHarness()));
    await tester.tap(find.text('Open Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Commute'));
    await tester.pumpAndSettle();

    expect(find.text('Commute'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Discover'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discover'), findsOneWidget);
  });

  testWidgets(
    'system Back pops Imported playlists to Library, then Library to Discover',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _NestedBackHarness()));
      await tester.tap(find.text('Open Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Imported playlists'));
      await tester.pumpAndSettle();

      expect(find.text('Imported playlists'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Discover'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discover'), findsOneWidget);
    },
  );

  testWidgets(
    'Back on Files does not pop a hidden Explore stack',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _IndexedTabBackHarness()));
      await tester.tap(find.text('Explore tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Commute'));
      await tester.pumpAndSettle();
      expect(find.text('Commute'), findsOneWidget);

      await tester.tap(find.text('Files tab'));
      await tester.pumpAndSettle();
      expect(find.text('Files root'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Home root'), findsOneWidget);
      expect(find.text('Commute'), findsNothing);
      expect(find.text('Explore canPop: true'), findsOneWidget);
      expect(find.text('Nested Back calls: 0'), findsOneWidget);

      await tester.tap(find.text('Explore tab'));
      await tester.pumpAndSettle();
      expect(find.text('Commute'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Discover'), findsNothing);
    },
  );
}

class _IndexedTabBackHarness extends StatefulWidget {
  const _IndexedTabBackHarness();

  @override
  State<_IndexedTabBackHarness> createState() => _IndexedTabBackHarnessState();
}

class _IndexedTabBackHarnessState extends State<_IndexedTabBackHarness> {
  final GlobalKey<NavigatorState> _exploreNavigatorKey =
      GlobalKey<NavigatorState>();
  int _activeTab = 2;
  int _nestedBackCalls = 0;
  late final _BackStackObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = _BackStackObserver(() {
      if (mounted) setState(() {});
    });
  }

  void _push(String title, List<Widget> actions) {
    _exploreNavigatorKey.currentState?.push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: title),
        builder: (_) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [Text(title), ...actions],
            ),
          ),
        ),
      ),
    );
  }

  Widget _exploreRoot() => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Discover'),
              ElevatedButton(
                onPressed: () => _push('Search', [
                  ElevatedButton(
                    onPressed: () => _push('Commute', const []),
                    child: const Text('Open Commute'),
                  ),
                ]),
                child: const Text('Open Search'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_activeTab == 1) setState(() => _activeTab = 2);
      },
      child: Scaffold(
        body: Column(
          children: [
            Text(
              'Explore canPop: ${_exploreNavigatorKey.currentState?.canPop() ?? false}',
            ),
            Text('Nested Back calls: $_nestedBackCalls'),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _activeTab = 0),
                  child: const Text('Explore tab'),
                ),
                TextButton(
                  onPressed: () => setState(() => _activeTab = 1),
                  child: const Text('Files tab'),
                ),
              ],
            ),
            Expanded(
              child: IndexedStack(
                index: _activeTab,
                children: [
                  NavigatorPopHandler<void>(
                    enabled: PocketLinkNavigation.shouldHandleNestedBack(
                      isActive: _activeTab == 0,
                      canPop: _exploreNavigatorKey.currentState?.canPop() ??
                          false,
                    ),
                    onPopWithResult: (_) {
                      if (_activeTab != 0) return;
                      _nestedBackCalls++;
                      _exploreNavigatorKey.currentState?.maybePop();
                      setState(() {});
                    },
                    child: Navigator(
                      key: _exploreNavigatorKey,
                      observers: [_observer],
                      onGenerateInitialRoutes: (_, __) => [
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(name: 'Discover'),
                          builder: (_) => _exploreRoot(),
                        ),
                      ],
                    ),
                  ),
                  PopScope<void>(
                    canPop: _activeTab != 1,
                    onPopInvokedWithResult: (didPop, result) {},
                    child: const Center(child: Text('Files root')),
                  ),
                  const Center(child: Text('Home root')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NestedBackHarness extends StatefulWidget {
  const _NestedBackHarness();

  @override
  State<_NestedBackHarness> createState() => _NestedBackHarnessState();
}

class _NestedBackHarnessState extends State<_NestedBackHarness> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _exploreCanPop = false;

  void _refreshCanPop() {
    final next = _navigatorKey.currentState?.canPop() ?? false;
    if (mounted && next != _exploreCanPop) {
      setState(() => _exploreCanPop = next);
    }
  }

  void _push(String title, List<Widget> actions) {
    _navigatorKey.currentState?.push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: title),
        builder: (_) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rootPage() => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Discover'),
              ElevatedButton(
                onPressed: () => _push('Search', [
                  ElevatedButton(
                    onPressed: () => _push('Commute', const []),
                    child: const Text('Open Commute'),
                  ),
                ]),
                child: const Text('Open Search'),
              ),
              ElevatedButton(
                onPressed: () => _push('Library', [
                  ElevatedButton(
                    onPressed: () => _push('Imported playlists', const []),
                    child: const Text('Open Imported playlists'),
                  ),
                ]),
                child: const Text('Open Library'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      // Match HomeScreen: permit the nested handler to own Back only while
      // Explore has a pushed route. NavigatorPopHandler then vetoes the root
      // route pop and dispatches the event to the nested Navigator.
      canPop: _exploreCanPop,
      child: NavigatorPopHandler<void>(
        enabled: _exploreCanPop,
        onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
        child: Navigator(
          key: _navigatorKey,
          observers: [
            _BackStackObserver(_refreshCanPop),
          ],
          onGenerateInitialRoutes: (_, __) => [
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'Discover'),
              builder: (_) => _rootPage(),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackStackObserver extends NavigatorObserver {
  _BackStackObserver(this.onChanged);

  final VoidCallback onChanged;

  void _notifyAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyAfterBuild();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyAfterBuild();
  }
}
