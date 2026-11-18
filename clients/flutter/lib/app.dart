import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'features/home/browser_state_store.dart';

import 'core/settings/app_settings.dart';
import 'core/logging/diagnostic_observer.dart';
import 'features/connection/connection_screen.dart';
import 'features/home/app_wide_controls.dart';

class PocketLinkApp extends StatefulWidget {
  const PocketLinkApp({super.key});

  @override
  State<PocketLinkApp> createState() => _PocketLinkAppState();
}

class _PocketLinkAppState extends State<PocketLinkApp> {
  final _settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_settingsChanged);
    _settings.load();
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_settingsChanged);
    super.dispose();
  }

  ThemeData _theme({required Brightness brightness, bool amoled = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF536DFE),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: amoled ? scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF080808),
        surfaceContainer: const Color(0xFF101010),
        surfaceContainerHigh: const Color(0xFF171717),
        surfaceContainerHighest: const Color(0xFF202020),
      ) : scheme,
      scaffoldBackgroundColor: amoled ? Colors.black : null,
      useMaterial3: true,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _PocketLinkPageTransitionsBuilder(),
        },
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _settings.themeMode;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserStateStore()),
        ChangeNotifierProvider<AppSettings>.value(value: _settings),
      ],
      child: MaterialApp(
      title: 'PocketLink',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [DiagnosticNavigatorObserver.instance],
      themeMode: mode,
      theme: _theme(brightness: Brightness.light),
      darkTheme: _theme(brightness: Brightness.dark, amoled: _settings.amoled),
      home: const ConnectionScreen(),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          MaterialUiCompatibilityBridge(
            child: child ?? const SizedBox.shrink(),
          ),
          const AppWideControls(),
        ],
      ),
      ),
    );
  }
}

/// A restrained spring-like route entrance. It animates only the incoming page;
/// the outgoing page and app-wide playback controls keep their own state.
class _PocketLinkPageTransitionsBuilder extends PageTransitionsBuilder {
  const _PocketLinkPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations) return child;

    final scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: scale, child: child),
    );
  }
}
