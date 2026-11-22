import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../../core/navigation/pocketlink_navigation.dart';
import 'navigation_dock.dart';
import 'music_shortcut_menu.dart';
import 'home_navigation_drawer.dart';
import 'network_route_classifier.dart';
import 'explore_search_screens.dart';
import 'home_dashboard.dart';
import '../media/media_player_screen.dart';
import '../media/now_playing_overlay_controller.dart';
import '../media/media_browser_screen.dart';
import '../media/media_library_catalog.dart';
import '../library/photo_gallery_screen.dart';
import '../media/persistent_audio_player.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../files/documents_browser_screen.dart';
import '../storage/local_storage_setup_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../transfers/transfer_manager_screen.dart';
import '../downloads/download_manager_service.dart';
import '../downloads/downloads_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, this.serverName, this.onReturnToConnection, super.key});

  final ServerApi api;
  final String? serverName;
  final VoidCallback? onReturnToConnection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _rootScaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _pageController;
  int _selectedIndex = 0;
  bool _hostSetupOpen = false;
  bool _hostSetupInitialized = false;
  final Set<int> _initializedTabs = {0};
  ExploreCategory _exploreCategory = ExploreCategory.files;
  String _fileCategory = 'All';
  int _externalDriveRequest = 0;
  int _fileLocationRequest = 0;
  int _uploadRequest = 0;
  bool _musicShortcutsExpanded = false;
  bool _filesCanNavigateBack = false;
  bool _openingNowPlaying = false;
  bool _libraryOpen = false;
  VoidCallback? _libraryBackHandler;
  VoidCallback? _tabBackHandler;
  Widget? _libraryPage;
  String? _requestedVolume;
  String _requestedPath = '';
  double? _horizontalDragStartX;
  double _horizontalDragDeltaX = 0;

  List<int> get _visibleTabIndices {
    final settings = AppSettings.instance;
    final indices = settings.navigationOrder
        .where((id) => id != 'browse' && settings.visibleNavigationItems.contains(id))
        .map((id) => switch (id) {
          'explore' => 1,
          'files' => 2,
          _ => 0,
        })
        .toList(growable: false);
    return indices.isEmpty ? const <int>[0] : indices;
  }

  int _pagePositionForTab(int tabIndex) {
    final position = _visibleTabIndices.indexOf(tabIndex);
    return position < 0 ? 0 : position;
  }

  void _syncPageToTab(int tabIndex, {bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final target = _pagePositionForTab(tabIndex);
      final current = _pageController.page;
      if (current != null && (current - target).abs() < 0.001) return;
      final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (!animate || reduceMotion) {
        _pageController.jumpToPage(target);
      } else {
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _onPageChanged(int page) {
    final tabs = _visibleTabIndices;
    if (page < 0 || page >= tabs.length) return;
    final nextIndex = tabs[page];
    if (_selectedIndex == nextIndex && _initializedTabs.contains(nextIndex)) {
      return;
    }
    if (_selectedIndex != nextIndex) {
      _tabBackHandler?.call();
      _tabBackHandler = null;
    }
    setState(() {
      _selectedIndex = nextIndex;
      _initializedTabs.add(nextIndex);
      _libraryOpen = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _pagePositionForTab(_selectedIndex));
    unawaited(DownloadManagerService.instance.initialize());
    DownloadManagerService.instance.bindServerApi(widget.api);
    PocketLinkNavigation.drawerOpen.value = false;
    PocketLinkNavigation.quickShortcutsOpen.value = false;
    PocketLinkNavigation.bottomDockVisible.value = true;
    AppSettings.instance.addListener(_navigationSettingsChanged);
  }

  void _openHostSetup() {
    setState(() {
      _libraryOpen = false;
      _hostSetupInitialized = true;
      _hostSetupOpen = true;
      PocketLinkNavigation.bottomDockVisible.value = false;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
    });
  }

  void _closeHostSetup() {
    if (!_hostSetupOpen) return;
    setState(() {
      _hostSetupOpen = false;
      PocketLinkNavigation.bottomDockVisible.value = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
    });
  }

  void _navigationSettingsChanged() {
    final settings = AppSettings.instance;
    if (!settings.musicButtonLongPressEnabled && _musicShortcutsExpanded) {
      setState(() => _musicShortcutsExpanded = false);
      PocketLinkNavigation.quickShortcutsOpen.value = false;
    }
    final selectedId = switch (_selectedIndex) {
      0 => 'home',
      1 => 'explore',
      2 => 'files',
      _ => 'home',
    };
    if (settings.visibleNavigationItems.contains(selectedId)) {
      _syncPageToTab(_selectedIndex, animate: false);
      return;
    }
    final nextId = settings.navigationOrder.firstWhere(
      (id) => id != 'browse' && settings.visibleNavigationItems.contains(id),
      orElse: () => 'home',
    );
    final nextIndex = switch (nextId) {
      'explore' => 1,
      'files' => 2,
      _ => 0,
    };
    if (mounted) {
      setState(() {
        _selectedIndex = nextIndex;
        _initializedTabs.add(nextIndex);
      });
      _syncPageToTab(nextIndex, animate: false);
    }
  }

  @override
  void dispose() {
    DownloadManagerService.instance.releaseServerApi(widget.api);
    AppSettings.instance.removeListener(_navigationSettingsChanged);
    _pageController.dispose();
    PocketLinkNavigation.drawerOpen.value = false;
    PocketLinkNavigation.quickShortcutsOpen.value = false;
    PocketLinkNavigation.bottomDockVisible.value = false;
    super.dispose();
  }

  void _openTab(int index) {
    _libraryBackHandler?.call();
    _tabBackHandler?.call();
    setState(() {
      _libraryBackHandler = null;
      _tabBackHandler = null;
      _libraryOpen = false;
      _hostSetupOpen = false;
      PocketLinkNavigation.bottomDockVisible.value = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(index);
      _selectedIndex = index;
    });
    _syncPageToTab(index);
  }

  void _onLibraryBackHandlerChanged(VoidCallback? handler) {
    if (!mounted || identical(_libraryBackHandler, handler)) return;
    setState(() => _libraryBackHandler = handler);
  }

  void _onTabBackHandlerChanged(VoidCallback? handler) {
    if (!mounted || identical(_tabBackHandler, handler)) return;
    setState(() => _tabBackHandler = handler);
  }

  void _openFileLocation(String? volume, String path) {
    setState(() {
      _libraryOpen = false;
      _hostSetupOpen = false;
      PocketLinkNavigation.bottomDockVisible.value = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _requestedVolume = volume;
      _requestedPath = path;
      _fileLocationRequest++;
    });
    _syncPageToTab(2);
  }

  void _openExternalStorage() {
    setState(() {
      _libraryOpen = false;
      _hostSetupOpen = false;

      PocketLinkNavigation.bottomDockVisible.value = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _externalDriveRequest++;
    });
    _syncPageToTab(2);
  }

  void _openExplore(ExploreCategory category, {String? fileCategory}) {
    if (fileCategory == 'Documents') {
      _openLibrary('documents');
      return;
    }
    setState(() {
      _libraryOpen = false;
      _hostSetupOpen = false;

      PocketLinkNavigation.bottomDockVisible.value = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(1);
      _exploreCategory = category;
      _fileCategory = fileCategory ?? 'All';
      _selectedIndex = 1;
    });
    _syncPageToTab(1);
  }


  void _openLibrary(String id) {
    _libraryBackHandler?.call();
    _tabBackHandler?.call();
    _libraryBackHandler = null;
    _tabBackHandler = null;
    final page = switch (id) {
      'music' => MediaBrowserScreen(api: widget.api, type: MediaLibraryType.music, onHome: _closeLibrary, onBackHandlerChanged: _onLibraryBackHandlerChanged),
      'videos' => MediaBrowserScreen(api: widget.api, type: MediaLibraryType.video, onHome: _closeLibrary, onBackHandlerChanged: _onLibraryBackHandlerChanged),
      'photos' => PhotoGalleryScreen(api: widget.api, onBackHandlerChanged: _onLibraryBackHandlerChanged),
      'favorites' => PhotoGalleryScreen(api: widget.api, initialTab: 2, onBackHandlerChanged: _onLibraryBackHandlerChanged),
      'documents' => DocumentsBrowserScreen(api: widget.api),
      'downloads' => DownloadsScreen(api: widget.api),
      _ => null,
    };
    if (page == null) return;
    setState(() {
      _hostSetupOpen = false;

      PocketLinkNavigation.bottomDockVisible.value = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _libraryPage = page;
      _libraryOpen = true;
    });
  }

  void _closeLibrary() {
    if (!_libraryOpen) return;
    _libraryBackHandler?.call();
    setState(() {
      _libraryBackHandler = null;
      _libraryOpen = false;
    });
  }

  void _openMusicShortcut(String id) {
    if (_musicShortcutsExpanded) {
      setState(() {
          _musicShortcutsExpanded = false;
          PocketLinkNavigation.quickShortcutsOpen.value = false;
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
      case 'videos':
      case 'photos':
      case 'documents':
      case 'favorites':
        _openLibrary(id);
        break;
      case 'upload':
        setState(() {
          _libraryOpen = false;
          _initializedTabs.add(2);
          _selectedIndex = 2;
          _uploadRequest++;
        });
        _syncPageToTab(2);
        break;
      case 'drives':
        _openExternalStorage();
        break;
      case 'search':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SearchScreen(
            api: widget.api,
            onHome: () => Navigator.of(context).maybePop(),
          ),
        ));
        break;
    }
  }

  void _expandMusicShortcuts() {
    if (!AppSettings.instance.musicButtonLongPressEnabled) return;
    HapticFeedback.lightImpact();
    setState(() => _musicShortcutsExpanded = true);
    PocketLinkNavigation.quickShortcutsOpen.value = true;
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
    if (player.isMusic &&
        player.isActive &&
        player.currentItem != null &&
        player.api != null) {
      NowPlayingOverlayController.open();
      return;
    }
    if (_openingNowPlaying) return;
    final item = player.currentItem;
    final api = player.api;
    if (player.isActive && item != null && api != null) {
      final originRect = PocketLinkNavigation.resolveMediaOriginRect(
        preferMiniPlayer: AppSettings.instance.showMiniPlayer &&
            player.shouldShowMiniPlayer,
      );
      _openingNowPlaying = true;
      try {
        await Navigator.of(context, rootNavigator: true).push<void>(
          PageRouteBuilder<void>(
            opaque: true,
            barrierColor: Colors.transparent,
            settings: const RouteSettings(
              name: PocketLinkRouteNames.nowPlaying,
            ),
            transitionDuration: const Duration(milliseconds: 420),
            reverseTransitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (_, __, ___) => MediaPlayerScreen(
              api: api,
              title: item.title,
              path: item.path,
              volume: item.volume,
              isVideo: true,
              queue: player.queue,
              initialIndex: player.currentIndex,
              resumeExisting: true,
            ),
            transitionsBuilder: (context, animation, __, child) =>
                PocketLinkNavigation.mediaContainerTransformTransition(
              context: context,
              animation: animation,
              child: child,
              originRect: originRect,
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final miniPlayerVisible = AppSettings.instance.showMiniPlayer && player.shouldShowMiniPlayer;
    final bottomSystemInset = MediaQuery.viewPaddingOf(context).bottom;
    final parsedServerHost = Uri.tryParse(widget.api.baseUrl)?.host;
    final serverHost = parsedServerHost == null || parsedServerHost.isEmpty
        ? widget.api.baseUrl
        : parsedServerHost;
    final drawerServerName = widget.serverName?.trim().isNotEmpty == true
        ? widget.serverName!.trim()
        : serverHost;
    final tabPages = <int, Widget>{
      0: HomeDashboard(
        api: widget.api,
        serverName: widget.serverName,
        onOpenExplore: _openExplore,
        onOpenLibrary: _openLibrary,
        onOpenFiles: () => _openTab(2),
        onOpenExternalStorage: _openExternalStorage,
        onOpenHostSetup: _openHostSetup,
        onOpenFileLocation: _openFileLocation,
        onReturnToConnection: widget.onReturnToConnection,
        onOpenDrawer: () => _rootScaffoldKey.currentState?.openDrawer(),
      ),
      1: _initializedTabs.contains(1)
          ? ExploreScreen(
              key: const PageStorageKey<String>('pocketlink-explore'),
              api: widget.api,
              category: _exploreCategory,
              fileCategory: _fileCategory,
              onBackAtRoot: () => _openTab(0),
              onOpenFiles: () => _openTab(2),
              onOpenLibrary: _openLibrary,
              onCategoryChanged: (category) => setState(() {
                _exploreCategory = category;
                if (category == ExploreCategory.files) _fileCategory = 'All';
              }),
            )
          : const SizedBox.shrink(),
      2: _initializedTabs.contains(2)
          ? FileManagerScreen(
              key: PageStorageKey<String>('pocketlink-files-${widget.api.baseUrl}'),
              api: widget.api,
              isActive: true,
              onBackAtRoot: () => _openTab(0),
              onCanNavigateBackChanged: (canNavigateBack) {
                if (_filesCanNavigateBack != canNavigateBack) {
                  setState(() => _filesCanNavigateBack = canNavigateBack);
                }
              },
              onBackHandlerChanged: _onTabBackHandlerChanged,
              externalDriveRequest: _externalDriveRequest,
              locationRequest: _fileLocationRequest,
              uploadRequest: _uploadRequest,
              requestedVolume: _requestedVolume,
              requestedPath: _requestedPath,
            )
          : const SizedBox.shrink(),
    };
    final visibleTabIndices = _visibleTabIndices;
    final pageIndices = <int, int>{
      for (var position = 0; position < visibleTabIndices.length; position++)
        visibleTabIndices[position]: position,
    };

    return PopScope(
      canPop: !_libraryOpen && !_hostSetupOpen && _selectedIndex == 0 &&
          !_musicShortcutsExpanded && _libraryBackHandler == null &&
          _tabBackHandler == null && !PocketLinkNavigation.drawerOpen.value,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (PocketLinkNavigation.drawerOpen.value) {
          _rootScaffoldKey.currentState?.closeDrawer();
        } else if (_tabBackHandler != null) {
          _tabBackHandler!.call();
        } else if (_libraryBackHandler != null) {
          _libraryBackHandler!.call();
        } else if (_libraryOpen) {
          _closeLibrary();
        } else if (_hostSetupOpen) {
          _closeHostSetup();
        } else if (_musicShortcutsExpanded) {
          setState(() {
            _musicShortcutsExpanded = false;
            PocketLinkNavigation.quickShortcutsOpen.value = false;
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
          key: _rootScaffoldKey,
          drawerScrimColor: Colors.black.withValues(alpha: 0.58),
          drawerEnableOpenDragGesture: false,
          drawer: PocketLinkHomeDrawer(
            serverName: drawerServerName,
            routeLabel: networkRouteLabel(serverHost),
            onOpenLibrary: _openMusicShortcut,
            onOpenFiles: () => _openTab(2),
            onConnectDrive: _openHostSetup,
            onOpenTransfers: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const TransferManagerScreen(),
              ),
            ),
            onOpenDownloads: () => _openLibrary('downloads'),
            onOpenSettings: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  onOpenSavedServers: widget.onReturnToConnection,
                ),
              ),
            ),
            onSwitchServer: widget.onReturnToConnection,
          ),
          onDrawerChanged: (opened) {
            PocketLinkNavigation.drawerOpen.value = opened;
            if (mounted) setState(() {});
            if (opened && _musicShortcutsExpanded) {
              setState(() => _musicShortcutsExpanded = false);
              PocketLinkNavigation.quickShortcutsOpen.value = false;
            }
          },
          extendBody: !_hostSetupOpen,
          body: Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: _musicShortcutsExpanded ? 16 : 0,
                ),
                duration: reduceMotion
                    ? Duration.zero
                    : Duration(milliseconds: _musicShortcutsExpanded ? 360 : 220),
                curve: Curves.easeOutCubic,
                builder: (context, blurSigma, child) => ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  enabled: blurSigma > 0.1,
                  child: child!,
                ),
                child: IgnorePointer(
                  ignoring: _libraryOpen || _hostSetupOpen,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: visibleTabIndices.length,
                    onPageChanged: _onPageChanged,
                    physics: _libraryOpen || _hostSetupOpen
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    itemBuilder: (context, page) {
                      final tabIndex = visibleTabIndices[page];
                      return _KeepAliveTab(
                        key: ValueKey<String>('pocketlink-tab-$tabIndex'),
                        child: tabPages[tabIndex] ?? const SizedBox.shrink(),
                      );
                    },
                  ),
                ),
              ),
              if (_libraryPage != null)
                Positioned.fill(
                  child: Offstage(
                    offstage: !_libraryOpen,
                    child: TickerMode(
                      enabled: _libraryOpen,
                      child: IgnorePointer(
                        ignoring: !_libraryOpen,
                        child: _libraryPage!,
                      ),
                    ),
                  ),
                ),
              if (_hostSetupInitialized)
                Positioned.fill(
                  child: Offstage(
                    offstage: !_hostSetupOpen,
                    child: TickerMode(
                      enabled: _hostSetupOpen,
                      child: IgnorePointer(
                        ignoring: !_hostSetupOpen,
                        child: LocalStorageSetupScreen(onHome: _closeHostSetup),
                      ),
                    ),
                  ),
                ),
              if (!_hostSetupOpen && !_libraryOpen)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      _horizontalDragStartX = details.globalPosition.dx;
                      _horizontalDragDeltaX = 0;
                    },
                    onHorizontalDragUpdate: (details) {
                      _horizontalDragDeltaX += details.delta.dx;
                    },
                    onHorizontalDragEnd: (details) {
                      final startX = _horizontalDragStartX;
                      final deltaX = _horizontalDragDeltaX;
                      _horizontalDragStartX = null;
                      _horizontalDragDeltaX = 0;
                      final isHomeRoot = _selectedIndex == 0 &&
                          !_musicShortcutsExpanded &&
                          !PocketLinkNavigation.drawerOpen.value;
                      if (startX != null &&
                          PocketLinkNavigation.shouldOpenDrawerFromEdgeSwipe(
                            startX: startX,
                            deltaX: deltaX,
                            isHome: isHomeRoot,
                          )) {
                        _rootScaffoldKey.currentState?.openDrawer();
                      }
                    },
                  ),
                ),
              if (!_hostSetupOpen)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_musicShortcutsExpanded,
                    child: AnimatedOpacity(
                      opacity: _musicShortcutsExpanded ? 0.36 : 0,
                      duration: reduceMotion
                          ? Duration.zero
                          : Duration(milliseconds: _musicShortcutsExpanded ? 360 : 220),
                      curve: Curves.easeOutCubic,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(
                          () {
                            _musicShortcutsExpanded = false;
                            PocketLinkNavigation.quickShortcutsOpen.value = false;
                          },
                        ),
                        child: const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              if (!_hostSetupOpen && _musicShortcutsExpanded)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: LayoutInsetsScope.of(context).bottomClearance + 8,
                  child: MusicShortcutMenu(
                    shortcuts: AppSettings.instance.musicButtonShortcuts,
                    expanded: true,
                    onSelect: _openMusicShortcut,
                  ),
                ),
              if (!_hostSetupOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PocketLinkBottomScrim(
                    height: PocketLinkLayoutMetrics.bottomOverlayHeight(
                      bottomInset: bottomSystemInset,
                      hasDock: true,
                      hasMiniPlayer: miniPlayerVisible,
                    ),
                  ),
                ),
              if (!_hostSetupOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingNavigationDock(
                    order: AppSettings.instance.navigationOrder,
                    visibleItems: AppSettings.instance.visibleNavigationItems,
                    selectedIndex: _selectedIndex,
                    pageController: _pageController,
                    pageIndices: pageIndices,
                    isPlaying: player.isMusic && player.isPlaying,
                    hasMedia: player.isActive && player.currentItem != null,
                    isVideo: player.isActive && !player.isMusic,
                    onSelect: _openTab,
                    musicShortcutsExpanded: _musicShortcutsExpanded,
                    onMusicShortcutDismissed: () {
                      if (_musicShortcutsExpanded) {
                        setState(() {
                          _musicShortcutsExpanded = false;
                          PocketLinkNavigation.quickShortcutsOpen.value = false;
                        });
                      }
                    },
                    onMusicShortcutLongPress: _expandMusicShortcuts,
                    onBrowseSwipeLeft: () => _handleMusicButtonSwipe(left: true),
                    onBrowseSwipeRight: () => _handleMusicButtonSwipe(left: false),
                    onBrowsePressed: () {
                      _closeHostSetup();
                      _openNowPlaying(player);
                    },
                  ),
                  ),
                ),
            ],
          ),
        ),
      ),
        ),
    );
  }
}





class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child, super.key});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin<_KeepAliveTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
