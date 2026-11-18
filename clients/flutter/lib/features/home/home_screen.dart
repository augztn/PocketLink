import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/navigation/pocketlink_navigation.dart';
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
import '../search/search_screen.dart';

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
  bool _musicShortcutsExpanded = false;
  bool _filesCanNavigateBack = false;
  bool _openingNowPlaying = false;
  String? _requestedVolume;
  String _requestedPath = '';

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_navigationSettingsChanged);
  }

  void _openHostSetup() {
    setState(() {
      _hostSetupInitialized = true;
      _hostSetupOpen = true;
      _quickShortcutsExpanded = false;
      _musicShortcutsExpanded = false;
    });
  }

  void _closeHostSetup() {
    if (!_hostSetupOpen) return;
    setState(() {
      _hostSetupOpen = false;
      _quickShortcutsExpanded = false;
      _musicShortcutsExpanded = false;
    });
  }

  void _navigationSettingsChanged() {
    final settings = AppSettings.instance;
    if (!settings.floatingShortcutEnabled && _quickShortcutsExpanded) {
      _quickShortcutsExpanded = false;
    }
    if (!settings.musicButtonLongPressEnabled && _musicShortcutsExpanded) {
      _musicShortcutsExpanded = false;
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
    super.dispose();
  }

  void _openTab(int index) => setState(() {
    _hostSetupOpen = false;
    _quickShortcutsExpanded = false;
    _musicShortcutsExpanded = false;
    _initializedTabs.add(index);
    _selectedIndex = index;
  });

  void _openFileLocation(String? volume, String path) {
    setState(() {
      _hostSetupOpen = false;
      _quickShortcutsExpanded = false;
      _musicShortcutsExpanded = false;
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
      _quickShortcutsExpanded = false;
      _musicShortcutsExpanded = false;
      _initializedTabs.add(1);
      _exploreCategory = category;
      _fileCategory = fileCategory ?? 'All';
      _selectedIndex = 1;
    });
  }


  void _openFloatingShortcut(String id) {
    if (_quickShortcutsExpanded || _musicShortcutsExpanded) {
      setState(() {
        _quickShortcutsExpanded = false;
        _musicShortcutsExpanded = false;
      });
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
      case 'search':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SearchScreen(
            api: widget.api,
            onHome: () => Navigator.of(context).maybePop(),
          ),
        ));
        break;
      case 'drives':
        _openExternalStorage();
        break;
    }
  }

  void _expandFloatingShortcuts() {
    HapticFeedback.lightImpact();
    setState(() {
      _quickShortcutsExpanded = true;
      _musicShortcutsExpanded = false;
    });
  }

  void _expandMusicShortcuts() {
    if (!AppSettings.instance.musicButtonLongPressEnabled) return;
    HapticFeedback.lightImpact();
    setState(() {
      _musicShortcutsExpanded = true;
      _quickShortcutsExpanded = false;
    });
  }

  void _handleMusicButtonSwipe({required bool left}) {
    final settings = AppSettings.instance;
    if (!settings.musicButtonSwipeEnabled) return;
    final action = left
        ? settings.musicButtonSwipeLeftAction
        : settings.musicButtonSwipeRightAction;
    switch (action) {
      case 'next':
        PersistentAudioPlayer.instance.skipToNext();
        break;
      case 'previous':
        PersistentAudioPlayer.instance.skipToPrevious();
        break;
    }
  }

  Future<void> _openNowPlaying(PersistentAudioPlayer player) async {
    if (_openingNowPlaying) return;
    final item = player.currentItem;
    final api = player.api;
    if (player.isActive && item != null && api != null) {
      _openingNowPlaying = true;
      try {
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(
              name: PocketLinkRouteNames.nowPlaying,
            ),
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
          ),
        );
      } finally {
        _openingNowPlaying = false;
      }
    } else {
      _openExplore(ExploreCategory.music);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PersistentAudioPlayer.instance;
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
      canPop: !_hostSetupOpen && _selectedIndex == 0 && !_quickShortcutsExpanded && !_musicShortcutsExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_hostSetupOpen) {
          _closeHostSetup();
        } else if (_quickShortcutsExpanded || _musicShortcutsExpanded) {
          setState(() {
            _quickShortcutsExpanded = false;
            _musicShortcutsExpanded = false;
          });
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
              if (!_hostSetupOpen && (_quickShortcutsExpanded || _musicShortcutsExpanded))
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _quickShortcutsExpanded = false;
                      _musicShortcutsExpanded = false;
                    }),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (!_hostSetupOpen && AppSettings.instance.floatingShortcutEnabled)
                Positioned(
                  right: 16,
                  bottom: 90 + MediaQuery.paddingOf(context).bottom,
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
              if (AppSettings.instance.showMiniPlayer && player.shouldShowMiniPlayer)
                const SizedBox(height: 62),
                FloatingNavigationDock(
                order: AppSettings.instance.navigationOrder,
                visibleItems: AppSettings.instance.visibleNavigationItems,
                selectedIndex: _selectedIndex,
                isPlaying: player.isMusic && player.isPlaying,
                hasMedia: player.isActive && player.currentItem != null,
                isVideo: player.isActive && !player.isMusic,
                onSelect: _openTab,
                musicShortcuts: AppSettings.instance.floatingShortcuts,
                musicShortcutsExpanded: _musicShortcutsExpanded,
                onMusicShortcutLongPress: _expandMusicShortcuts,
                onMusicShortcutSelected: _openFloatingShortcut,
                onBrowseSwipeLeft: () => _handleMusicButtonSwipe(left: true),
                onBrowseSwipeRight: () => _handleMusicButtonSwipe(left: false),
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



