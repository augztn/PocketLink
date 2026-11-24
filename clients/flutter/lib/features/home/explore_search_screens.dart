import 'package:material_ui/material_ui.dart';

import '../../core/logging/app_logger.dart';

import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../files/file_manager_screen.dart';
import '../files/documents_browser_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../media/media_browser_screen.dart';
import '../media/discover/discover_screen.dart';
import '../media/media_library_catalog.dart';
import '../search/search_screen.dart';
import '../downloads/download_manager_service.dart';
import '../downloads/downloads_screen.dart';
import '../storage/storage_browser_screen.dart';
import '../transfers/transfer_manager_screen.dart';
import '../settings/settings_screen.dart';

enum ExploreCategory { files, photos, music, videos }

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    required this.api,
    required this.category,
    required this.onCategoryChanged,
    this.fileCategory = 'All',
    this.onBackAtRoot,
    this.onOpenFiles,
    this.onOpenLibrary,
    this.onCanPopChanged,
    super.key,
  });

  final ServerApi api;
  final ExploreCategory category;
  final ValueChanged<ExploreCategory> onCategoryChanged;
  final String fileCategory;
  final VoidCallback? onBackAtRoot;
  final VoidCallback? onOpenFiles;
  final ValueChanged<String>? onOpenLibrary;
  final ValueChanged<bool>? onCanPopChanged;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _ExploreNavigatorObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = _ExploreNavigatorObserver(() {
      if (!mounted) return;
      setState(() {});
      widget.onCanPopChanged?.call(_navigatorKey.currentState?.canPop() ?? false);
    });
  }

  @override
  void dispose() {
    widget.onCanPopChanged?.call(false);
    super.dispose();
  }

  void _open(Widget screen) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: screen.runtimeType.toString()),
        builder: (_) => screen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<void>(
      enabled: _navigatorKey.currentState?.canPop() ?? false,
      onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
      child: PocketLinkNavigationScope(
        onHome: () {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
          widget.onBackAtRoot?.call();
        },
        child: Navigator(
        key: _navigatorKey,
        observers: [_observer],
        onGenerateInitialRoutes: (navigator, initialRoute) => [
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/'),
            builder: (_) => _ExploreGrid(
              api: widget.api,
              onHome: widget.onBackAtRoot,
              onOpen: _open,
              onOpenFiles: widget.onOpenFiles,
              onOpenLibrary: widget.onOpenLibrary,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ExploreNavigatorObserver extends NavigatorObserver {
  _ExploreNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;

  String _label(Route<dynamic>? route) {
    if (route == null) return 'none';
    final name = route.settings.name;
    return name == null || name.isEmpty ? route.runtimeType.toString() : name;
  }

  void _record(String action, Route<dynamic>? route, Route<dynamic>? related) {
    AppLogger.event('explore_navigation.$action', category: 'navigation',
      component: 'explore_navigator',
      fields: {'route_type': _label(route), 'related_route_type': _label(related)});
    onChanged();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('push', route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('pop', route, previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('remove', route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record('replace', newRoute, oldRoute);
}

class _ExploreGrid extends StatefulWidget {
  const _ExploreGrid({
    required this.api,
    required this.onHome,
    required this.onOpen,
    required this.onOpenFiles,
    required this.onOpenLibrary,
  });

  final ServerApi api;
  final VoidCallback? onHome;
  final ValueChanged<Widget> onOpen;
  final VoidCallback? onOpenFiles;
  final ValueChanged<String>? onOpenLibrary;

  @override
  State<_ExploreGrid> createState() => _ExploreGridState();
}

class _ExploreGridState extends State<_ExploreGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  bool _motionPreferenceApplied = false;

  ServerApi get api => widget.api;
  VoidCallback? get onHome => widget.onHome;
  ValueChanged<Widget> get onOpen => widget.onOpen;
  VoidCallback? get onOpenFiles => widget.onOpenFiles;

  void _openLibrary(String id, Widget fallback) {
    final callback = widget.onOpenLibrary;
    if (callback != null) {
      callback(id);
    } else {
      onOpen(fallback);
    }
  }

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionPreferenceApplied) return;
    _motionPreferenceApplied = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entryController.value = 1;
    } else {
      _entryController.forward();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _scanAllLibraries() async {
    try {
      await api.startMediaIndexScan();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library scan started.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the library scan.')),
      );
    }
  }

  Widget _staggeredCard(int index, Widget child) {
    final start = (index * 0.07).clamp(0.0, 0.5).toDouble();
    final animation = CurvedAnimation(
      parent: _entryController,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - progress)),
            child: Transform.scale(
              scale: 0.97 + (0.03 * progress),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget card({
      required int index,
      required String title,
      required String subtitle,
      required IconData icon,
      required Color tint,
      String? badge,
      required VoidCallback onTap,
    }) {
      return _staggeredCard(index, Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.onSurface.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, color: tint, size: 25),
                    ),
                    const Spacer(),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: tint,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                )),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        showHome: false,
        automaticallyImplyLeading: false,
        title: const Text('Explore'),
        actions: [
          PocketLinkAppBarAction(
            label: 'Download manager',
            icon: Icons.download_rounded,
            onPressed: () => onOpen(DownloadsScreen(api: api)),
          ),
          PocketLinkAppBarAction(
            label: 'Transfers',
            icon: Icons.swap_vert_rounded,
            onPressed: () => onOpen(const TransferManagerScreen()),
          ),
          PocketLinkAppBarAction(
            label: 'Drives & storage',
            icon: Icons.storage_rounded,
            onPressed: () => onOpen(StorageBrowserScreen(api: api)),
          ),
          PocketLinkAppBarAction(
            label: 'Scan all libraries',
            icon: Icons.refresh_rounded,
            onPressed: _scanAllLibraries,
            dividerBefore: true,
          ),
          PocketLinkAppBarAction(
            label: 'Settings',
            icon: Icons.settings_rounded,
            onPressed: () => onOpen(const SettingsScreen()),
            dividerBefore: true,
          ),
        ],
      ),
      body: GridView.count(
        padding: EdgeInsets.fromLTRB(16, LayoutInsetsScope.of(context).topClearance, 16, LayoutInsetsScope.of(context).bottomClearance),
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
        children: [
          card(
            index: 0,
            title: 'Photos', subtitle: 'Your picture collection',
            icon: Icons.photo_library_rounded, tint: const Color(0xFFE5A044),
            onTap: () => _openLibrary('photos', PhotoGalleryScreen(api: api)),
          ),
          card(
            index: 1,
            title: 'Music', subtitle: 'Albums and playlists',
            icon: Icons.headphones_rounded, tint: const Color(0xFF8D72E8),
            onTap: () => _openLibrary('music', MediaBrowserScreen(
              api: api,
              type: MediaLibraryType.music,
              onHome: () => Navigator.of(context).maybePop(),
            )),
          ),
          if (AppSettings.instance.discoverEnabled)
            card(
              index: 7,
              title: 'Discover', subtitle: 'YouTube Music and local lossless',
              icon: Icons.explore_rounded, tint: const Color(0xFFDB79A8),
              onTap: () => onOpen(DiscoverScreen(api: api)),
            ),
          card(
            index: 2,
            title: 'Videos', subtitle: 'Movies and clips',
            icon: Icons.play_circle_fill_rounded, tint: const Color(0xFF279D91),
            onTap: () => _openLibrary('videos', MediaBrowserScreen(
              api: api,
              type: MediaLibraryType.video,
              onHome: () => Navigator.of(context).maybePop(),
            )),
          ),
          card(
            index: 3,
            title: 'Documents', subtitle: 'PDF, Office and text',
            icon: Icons.description_rounded, tint: const Color(0xFF4C8ED9),
            onTap: () => _openLibrary('documents', DocumentsBrowserScreen(api: api)),
          ),
          card(
            index: 4,
            title: 'Files', subtitle: 'Browse server folders',
            icon: Icons.folder_rounded, tint: const Color(0xFF7186C8),
            onTap: onOpenFiles ?? () => onOpen(FileManagerScreen(api: api)),
          ),
          card(
            index: 5,
            title: 'Search', subtitle: 'Find files across storage',
            icon: Icons.search_rounded, tint: const Color(0xFF6C9DCE),
            onTap: () => onOpen(SearchScreen(api: api, onHome: () => Navigator.of(context).maybePop())),
          ),
          AnimatedBuilder(
            animation: DownloadManagerService.instance,
            builder: (context, _) {
              final manager = DownloadManagerService.instance;
              return card(
                index: 6,
                title: 'Downloads',
                subtitle: manager.activeCount > 0
                    ? '${manager.activeCount} downloading'
                    : manager.queuedCount > 0
                        ? '${manager.queuedCount} queued'
                        : 'Manage downloads',
                icon: Icons.download_rounded,
                badge: manager.activeCount > 0
                    ? '${manager.activeCount} active'
                    : null,
                tint: const Color(0xFF3FAD8A),
                onTap: () => _openLibrary(
                  'downloads',
                  DownloadsScreen(api: api),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
