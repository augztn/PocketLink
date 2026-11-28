import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:provider/provider.dart';

import 'features/files/file_browser_state_store.dart';
import 'features/media/media_browser_state_store.dart';

import 'core/settings/app_settings.dart';
import 'core/logging/diagnostic_observer.dart';
import 'core/widgets/persistent_overlay_host.dart';
import 'core/navigation/pocketlink_navigation.dart';
import 'core/navigation/pocketlink_page_transitions.dart';
import 'features/media/global_media_overlay.dart';
import 'features/connection/connection_screen.dart';

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
    final isDark = brightness == Brightness.dark;
    final seed = ColorScheme.fromSeed(
      seedColor: Color(_settings.accentColorValue),
      brightness: brightness,
    );
    final scheme = isDark
        ? seed.copyWith(
            primary: seed.primary,
            onPrimary: seed.onPrimary,
            primaryContainer: seed.primaryContainer,
            onPrimaryContainer: seed.onPrimaryContainer,
            secondary: const Color(0xFF2DD4BF),
            onSecondary: const Color(0xFF002024),
            secondaryContainer: const Color(0xFF12343A),
            onSecondaryContainer: const Color(0xFF9AF0FA),
            tertiary: const Color(0xFF8D72E8),
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFF2D2452),
            onTertiaryContainer: const Color(0xFFE9DDFF),
            surface: const Color(0xFF0A0B0E),
            onSurface: const Color(0xFFF3F5FA),
            onSurfaceVariant: const Color(0xFFA0A7BA),
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF1E2025),
            surfaceContainer: const Color(0xFF161618),
            surfaceContainerHigh: const Color(0xFF22252C),
            surfaceContainerHighest: const Color(0xFF2A2D36),
            outline: const Color(0xFF343844),
            outlineVariant: const Color(0xFF252832),
            error: const Color(0xFFFF6B6B),
          )
        : seed.copyWith(
            primary: seed.primary,
            onPrimary: seed.onPrimary,
            primaryContainer: seed.primaryContainer,
            onPrimaryContainer: seed.onPrimaryContainer,
            secondary: const Color(0xFF0E8FA0),
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFD4F2F6),
            onSecondaryContainer: const Color(0xFF00363D),
            tertiary: const Color(0xFF6D4AFF),
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFFEDE8FF),
            onTertiaryContainer: const Color(0xFF28127A),
            surface: Colors.white,
            onSurface: const Color(0xFF131726),
            onSurfaceVariant: const Color(0xFF525A74),
            error: const Color(0xFFDC2626),
            onError: Colors.white,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Colors.white,
            surfaceContainer: const Color(0xFFEBEFF8),
            surfaceContainerHigh: const Color(0xFFE1E6F3),
            surfaceContainerHighest: const Color(0xFFD5DCEB),
            outline: const Color(0xFF6A738D),
            outlineVariant: const Color(0xFFD6DCEC),
          );
    final effectiveScheme = amoled && isDark
        ? scheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF0C0D10),
            surfaceContainer: const Color(0xFF121316),
            surfaceContainerHigh: const Color(0xFF18191E),
            surfaceContainerHighest: const Color(0xFF22242B),
          )
        : scheme;

    final baseTextTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme;

    return ThemeData(
      colorScheme: effectiveScheme,
      scaffoldBackgroundColor: isDark
          ? Colors.black
          : const Color(0xFFF8FAFC),
      textTheme: baseTextTheme,
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PocketLinkPageTransitionsBuilder(),
          TargetPlatform.iOS: PocketLinkPageTransitionsBuilder(),
          TargetPlatform.linux: PocketLinkPageTransitionsBuilder(),
          TargetPlatform.macOS: PocketLinkPageTransitionsBuilder(),
          TargetPlatform.windows: PocketLinkPageTransitionsBuilder(),
        },
      ),
      visualDensity: VisualDensity.standard,
      dividerColor: effectiveScheme.outlineVariant.withValues(alpha: 0.7),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: effectiveScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: effectiveScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: effectiveScheme.primary,
            width: 1.4,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: effectiveScheme.surfaceContainerLow,
        modalBackgroundColor: effectiveScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _settings.themeMode;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FileBrowserStateStore()),
        ChangeNotifierProvider(create: (_) => MediaBrowserStateStore()),
        ChangeNotifierProvider<AppSettings>.value(value: _settings),
      ],
      child: MaterialApp(
      title: 'PocketLink',
      debugShowCheckedModeBanner: false,
      navigatorKey: PocketLinkNavigation.navigatorKey,
      navigatorObservers: [
        DiagnosticNavigatorObserver.instance,
        PocketLinkNavigation.observer,
      ],
      themeMode: mode,
      theme: _theme(brightness: Brightness.light),
      darkTheme: _theme(brightness: Brightness.dark, amoled: _settings.amoled),
      home: const ConnectionScreen(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final reduceMotion = media.disableAnimations || !_settings.animationsEnabled;
        // Scheduler time dilation affects every Flutter ticker in PocketLink,
        // not only Discover or route transitions. Playback itself is untouched.
        timeDilation = reduceMotion ? 0.01 : _settings.animationTimeDilation;
        final isLight = Theme.of(context).brightness == Brightness.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
            statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness:
                isLight ? Brightness.dark : Brightness.light,
          ),
          child: MediaQuery(
            data: media.copyWith(disableAnimations: reduceMotion),
            child: MaterialUiCompatibilityBridge(
              child: PersistentOverlayHost(
                child: GlobalMediaOverlay(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      ),
    );
  }
}
