import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import 'navigation_dock.dart';
import 'floating_quick_shortcut.dart';
import 'explore_search_screens.dart';
import 'home_dashboard.dart';
import '../media/media_player_screen.dart';
import '../media/now_playing_screen.dart';
import '../media/media_browser_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../media/persistent_audio_player.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../files/documents_browser_screen.dart';
import '../storage/local_storage_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, this.serverName, this.onReturnToConnection, super.key});

  final ServerApi api;
  final String? serverName;
  final VoidCallback? onReturnToConnection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _hostSetupOpen = false;
  bool _hostSetupInitialized = false;
  final Set<int> _initializedTabs = {0};
  ExploreCategory _exploreCategory = ExploreCategory.files;
  String _fileCategory = 'All';
  int _externalDriveRequest = 0;
  int _fileLocationRequest = 0;
  int _uploadRequest = 0;
  bool _quickShortcutsExpanded = false;
  bool _filesCanNavigateBack = false;
  bool _miniPlayerDismissed = false;
  bool _nowPlayingRouteOpen = false;
  late bool _lastPlayerPlaying;
  String? _requestedVolume;
  String _requestedPath = '';

  @override
  void initState() {
    super.initState();
    _lastPlayerPlaying = PersistentAudioPlayer.instance.isPlaying;
    PersistentAudioPlayer.instance.addListener(_playerStateChanged);
    AppSettings.instance.addListener(_navigationSettingsChanged);
  }

  void _playerStateChanged() {
    final isPlaying = PersistentAudioPlayer.instance.isPlaying;
    if (isPlaying && !_lastPlayerPlaying && _miniPlayerDismissed && mounted) {
      setState(() => _miniPlayerDismissed = false);
    }
    _lastPlayerPlaying = isPlaying;
  }

  void _dismissMiniPlayer() {
    if (PersistentAudioPlayer.instance.isPlaying || _miniPlayerDismissed) return;
    setState(() => _miniPlayerDismissed = true);
  }

  void _openHostSetup() {
    setState(() {
      _hostSetupInitialized = true;
      _hostSetupOpen = true;
      _quickShortcutsExpanded = false;
    });
  }

  void _closeHostSetup() {
    if (!_hostSetupOpen) return;
    setState(() => _hostSetupOpen = false);
  }

  void _navigationSettingsChanged() {
    final settings = AppSettings.instance;
    if (!settings.floatingShortcutEnabled && _quickShortcutsExpanded) {
      _quickShortcutsExpanded = false;
    }
    final selectedId = switch (_selectedIndex) {
      0 => 'home',
      1 => 'explore',
      2 => 'files',
      _ => 'home',
    };
    if (settings.visibleNavigationItems.contains(selectedId)) return;
    final nextId = settings.navigationOrder.firstWhere(
      (id) => id != 'browse' && settings.visibleNavigationItems.contains(id),
      orElse: () => 'home',
    );
    final nextIndex = switch (nextId) {
      'explore' => 1,
      'files' => 2,
      _ => 0,
    };
    if (mounted) setState(() {
      _selectedIndex = nextIndex;
      _initializedTabs.add(nextIndex);
    });
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_navigationSettingsChanged);
    PersistentAudioPlayer.instance.removeListener(_playerStateChanged);
    super.dispose();
  }

  void _openTab(int index) => setState(() {
    _hostSetupOpen = false;
    _initializedTabs.add(index);
    _selectedIndex = index;
  });

  void _openFileLocation(String? volume, String path) {
    setState(() {
      _hostSetupOpen = false;
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _requestedVolume = volume;
      _requestedPath = path;
      _fileLocationRequest++;
    });
  }

  void _openExternalStorage() {
    setState(() {
      _hostSetupOpen = false;
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _externalDriveRequest++;
    });
  }

  void _openExplore(ExploreCategory category, {String? fileCategory}) {
    if (fileCategory == 'Documents') {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DocumentsBrowserScreen(api: widget.api),
      ));
      return;
    }
    setState(() {
      _hostSetupOpen = false;
      _initializedTabs.add(1);
      _exploreCategory = category;
      _fileCategory = fileCategory ?? 'All';
      _selectedIndex = 1;
    });
  }


  void _openFloatingShortcut(String id) {
    if (_quickShortcutsExpanded) {
      setState(() => _quickShortcutsExpanded = false);
    }
    switch (id) {
      case 'explore':
        _openTab(1);
        break;
      case 'files':
        _openTab(2);
        break;
      case 'music':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowserScreen(
            api: widget.api,
            type: MediaLibraryType.music,
            onHome: () => Navigator.of(context).maybePop(),
          ),
        ));
        break;
      case 'videos':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowserScreen(
            api: widget.api,
            type: MediaLibraryType.video,
            onHome: () => Navigator.of(context).maybePop(),
          ),
        ));
        break;
      case 'photos':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PhotoGalleryScreen(api: widget.api),
        ));
        break;
      case 'documents':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DocumentsBrowserScreen(api: widget.api),
        ));
        break;
      case 'favorites':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PhotoGalleryScreen(api: widget.api, initialTab: 2),
        ));
        break;
      case 'upload':
        setState(() {
          _initializedTabs.add(2);
          _selectedIndex = 2;
          _uploadRequest++;
        });
        break;
    }
  }

  void _expandFloatingShortcuts() {
    HapticFeedback.lightImpact();
    setState(() => _quickShortcutsExpanded = true);
  }

  Future<void> _openNowPlaying(PersistentAudioPlayer player) async {
    if (_nowPlayingRouteOpen) return;
    final item = player.currentItem;
    final api = player.api;
    if (player.isActive && item != null && api != null) {
      setState(() => _nowPlayingRouteOpen = true);
      try {
        await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => player.isMusic
              ? NowPlayingScreen(
                  api: api,
                  queue: player.queue,
                  initialIndex: player.currentIndex,
                  resumeExisting: true,
                )
              : MediaPlayerScreen(
                  api: api,
                  title: item.title,
                  path: item.path,
                  volume: item.volume,
                  isVideo: true,
                  queue: player.queue,
                  initialIndex: player.currentIndex,
                  resumeExisting: true,
                ),
        ));
      } finally {
        if (mounted) setState(() => _nowPlayingRouteOpen = false);
      }
    } else {
      _openExplore(ExploreCategory.music);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PersistentAudioPlayer.instance;
    final showMiniPlayer = AppSettings.instance.showMiniPlayer &&
        player.isMusic &&
        player.isActive &&
        player.currentItem != null &&
        !_miniPlayerDismissed &&
        !_nowPlayingRouteOpen;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    // Keep the floating shortcut above the mini-player instead of letting
    // both controls occupy the same bottom-right area.
    final shortcutBottom = 90 + bottomSafeArea + (showMiniPlayer ? 66 : 0);
    final pages = [
      HomeDashboard(
        api: widget.api,
        serverName: widget.serverName,
        onOpenExplore: _openExplore,
        onOpenFiles: () => _openTab(2),
        onOpenExternalStorage: _openExternalStorage,
        onOpenHostSetup: _openHostSetup,
        onOpenFileLocation: _openFileLocation,
        onReturnToConnection: widget.onReturnToConnection,
      ),
      if (_initializedTabs.contains(1))
        ExploreScreen(
          key: const PageStorageKey<String>('pocketlink-explore'),
          api: widget.api,
          category: _exploreCategory,
          fileCategory: _fileCategory,
          onBackAtRoot: () => _openTab(0),
          onOpenFiles: () => _openTab(2),
          onOpenExternalStorage: _openExternalStorage,
          onCategoryChanged: (category) => setState(() {
            _exploreCategory = category;
            if (category == ExploreCategory.files) _fileCategory = 'All';
          }),
        )
      else
        const SizedBox.shrink(),
      if (_initializedTabs.contains(2))
        FileManagerScreen(
          key: PageStorageKey<String>('pocketlink-files-${widget.api.baseUrl}'),
          api: widget.api,
          isActive: true,
          onBackAtRoot: () => _openTab(0),
          onCanNavigateBackChanged: (canNavigateBack) {
            if (_filesCanNavigateBack != canNavigateBack) {
              setState(() => _filesCanNavigateBack = canNavigateBack);
            }
          },
          externalDriveRequest: _externalDriveRequest,
          locationRequest: _fileLocationRequest,
          uploadRequest: _uploadRequest,
          requestedVolume: _requestedVolume,
          requestedPath: _requestedPath,
        )
      else
        const SizedBox.shrink(),
      if (_hostSetupInitialized)
        LocalStorageSetupScreen(onHome: _closeHostSetup)
      else
        const SizedBox.shrink(),
    ];

    return PopScope(
      canPop: !_hostSetupOpen && _selectedIndex == 0 && !_quickShortcutsExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_hostSetupOpen) {
          _closeHostSetup();
        } else if (_quickShortcutsExpanded) {
          setState(() => _quickShortcutsExpanded = false);
        } else if (_selectedIndex == 2 && _filesCanNavigateBack) {
          // FileManagerScreen handles folder-level back navigation.
        } else if (_selectedIndex != 0) {
          _openTab(0);
        }
      },
      child: AnimatedBuilder(
        animation: AppSettings.instance,
        builder: (context, __) => AnimatedBuilder(
        animation: player,
        builder: (context, _) => Scaffold(
          extendBody: !_hostSetupOpen,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onHorizontalDragEnd: (details) {
                  if (_hostSetupOpen) return;
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 300) return;
                  final settings = AppSettings.instance;
                  final visibleTabs = settings.navigationOrder
                      .where((id) => id != 'browse' && settings.visibleNavigationItems.contains(id))
                      .map((id) => switch (id) {
                        'explore' => 1,
                        'files' => 2,
                        _ => 0,
                      })
                      .toList(growable: false);
                  final currentPosition = visibleTabs.indexOf(_selectedIndex);
                  if (currentPosition < 0) return;
                  final nextPosition = velocity < 0
                      ? (currentPosition + 1).clamp(0, visibleTabs.length - 1)
                      : (currentPosition - 1).clamp(0, visibleTabs.length - 1);
                  final nextIndex = visibleTabs[nextPosition];
                  if (nextIndex != _selectedIndex) _openTab(nextIndex);
                },
                child: IndexedStack(index: _hostSetupOpen ? 3 : _selectedIndex, children: pages),
              ),
              if (!_hostSetupOpen && AppSettings.instance.floatingShortcutEnabled && _quickShortcutsExpanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _quickShortcutsExpanded = false),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (!_hostSetupOpen && AppSettings.instance.floatingShortcutEnabled)
                Positioned(
                  right: 16,
                  bottom: shortcutBottom,
                  child: FloatingQuickShortcut(
                    shortcuts: AppSettings.instance.floatingShortcuts,
                    expanded: _quickShortcutsExpanded,
                    useLiquidGlass: AppSettings.instance.useLiquidGlass,
                    onTap: () {
                      final settings = AppSettings.instance;
                      if (settings.floatingShortcutTapAction == 'menu') {
                        _expandFloatingShortcuts();
                      } else {
                        _openFloatingShortcut(settings.floatingShortcuts.first);
                      }
                    },
                    onLongPress: _expandFloatingShortcuts,
                    longPressEnabled: AppSettings.instance.floatingShortcutLongPressEnabled,
                    onSelect: _openFloatingShortcut,
                  ),
                ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.bottomCenter,
                child: showMiniPlayer
                    ? _MiniPlayerBar(
                        player: player,
                        onOpen: () => _openNowPlaying(player),
                        onDismiss: _dismissMiniPlayer,
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
                FloatingNavigationDock(
                order: AppSettings.instance.navigationOrder,
                visibleItems: AppSettings.instance.visibleNavigationItems,
                selectedIndex: _selectedIndex,
                isPlaying: player.isMusic && player.isPlaying,
                hasMedia: player.isActive && player.currentItem != null,
                isVideo: player.isActive && !player.isMusic,
                onSelect: _openTab,
                onBrowsePressed: () {
                  _closeHostSetup();
                  _openNowPlaying(player);
                },
              ),
            ],
          ),
        ),
      ),
        ),
    );
  }
}



class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({required this.player, required this.onOpen, required this.onDismiss});

  final PersistentAudioPlayer player;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (!player.isPlaying && velocity > 300) onDismiss();
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: SizedBox(
            height: 58,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.music_note_rounded, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Text('NOW PLAYING', style: TextStyle(fontSize: 9, letterSpacing: 1.1)),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.player.stream.playing,
                  initialData: player.player.state.playing,
                  builder: (context, snapshot) => IconButton(
                    tooltip: (snapshot.data ?? false) ? 'Pause' : 'Play',
                    onPressed: player.togglePlayback,
                    icon: Icon((snapshot.data ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                ),
                IconButton(
                  tooltip: 'Next track',
                  onPressed: player.skipToNext,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
