import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/home/browser_state_store.dart';

import 'core/settings/app_settings.dart';
import 'features/connection/connection_screen.dart';

class HomeServerApp extends StatefulWidget {
  const HomeServerApp({super.key});

  @override
  State<HomeServerApp> createState() => _HomeServerAppState();
}

class _HomeServerAppState extends State<HomeServerApp> {
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
      title: 'HomeServer',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: _theme(brightness: Brightness.light),
      darkTheme: _theme(brightness: Brightness.dark, amoled: _settings.amoled),
      home: const ConnectionScreen(),
      builder: (context, child) => child ?? const SizedBox.shrink(),
      ),
    );
  }
}
