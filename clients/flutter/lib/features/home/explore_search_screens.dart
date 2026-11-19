import 'package:material_ui/material_ui.dart';

import '../../core/network/server_api.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../files/file_manager_screen.dart';
import '../files/documents_browser_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../media/media_browser_screen.dart';
import '../search/search_screen.dart';

enum ExploreCategory { files, photos, music, videos }

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    required this.api,
    required this.category,
    required this.onCategoryChanged,
    this.fileCategory = 'All',
    this.onBackAtRoot,
    this.onOpenFiles,
    super.key,
  });

  final ServerApi api;
  final ExploreCategory category;
  final ValueChanged<ExploreCategory> onCategoryChanged;
  final String fileCategory;
  final VoidCallback? onBackAtRoot;
  final VoidCallback? onOpenFiles;

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
      if (mounted) setState(() {});
    });
  }

  void _open(Widget screen) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
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

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onChanged();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => onChanged();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => onChanged();
}

class _ExploreGrid extends StatefulWidget {
  const _ExploreGrid({
    required this.api,
    required this.onHome,
    required this.onOpen,
    required this.onOpenFiles,
  });

  final ServerApi api;
  final VoidCallback? onHome;
  final ValueChanged<Widget> onOpen;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onOpenExternalStorage;

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
  VoidCallback? get onOpenExternalStorage => widget.onOpenExternalStorage;

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
        title: const Text('Explore'),
        onHome: onHome,
        leading: onHome == null ? null : IconButton(
          tooltip: 'Back to Dashboard',
          onPressed: onHome,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: GridView.count(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 12, 16, 112 + MediaQuery.paddingOf(context).bottom),
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
        children: [
          card(
            index: 0,
            title: 'Photos', subtitle: 'Your picture collection',
            icon: Icons.photo_library_rounded, tint: const Color(0xFFE5A044),
            onTap: () => onOpen(PhotoGalleryScreen(api: api)),
          ),
          card(
            index: 1,
            title: 'Music', subtitle: 'Albums and playlists',
            icon: Icons.headphones_rounded, tint: const Color(0xFF8D72E8),
            onTap: () => onOpen(MediaBrowserScreen(
              api: api,
              type: MediaLibraryType.music,
              onHome: () => Navigator.of(context).maybePop(),
            )),
          ),
          card(
            index: 2,
            title: 'Videos', subtitle: 'Movies and clips',
            icon: Icons.play_circle_fill_rounded, tint: const Color(0xFF279D91),
            onTap: () => onOpen(MediaBrowserScreen(
              api: api,
              type: MediaLibraryType.video,
              onHome: () => Navigator.of(context).maybePop(),
            )),
          ),
          card(
            index: 3,
            title: 'Documents', subtitle: 'PDF, Office and text',
            icon: Icons.description_rounded, tint: const Color(0xFF4C8ED9),
            onTap: () => onOpen(DocumentsBrowserScreen(api: api)),
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
        ],
      ),
    );
  }
}
