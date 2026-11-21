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

  @override
  void initState() {
    super.initState();
    unawaited(DownloadManagerService.instance.initialize());
    DownloadManagerService.instance.bindServerApi(widget.api);
    PocketLinkNavigation.drawerOpen.value = false;
    PocketLinkNavigation.quickShortcutsOpen.value = false;
    AppSettings.instance.addListener(_navigationSettingsChanged);
  }

  void _openHostSetup() {
    setState(() {
      _libraryOpen = false;
      _hostSetupInitialized = true;
      _hostSetupOpen = true;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
    });
  }

  void _closeHostSetup() {
    if (!_hostSetupOpen) return;
    setState(() {
      _hostSetupOpen = false;
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
    PocketLinkNavigation.drawerOpen.value = false;
    PocketLinkNavigation.quickShortcutsOpen.value = false;
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
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(index);
      _selectedIndex = index;
    });
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
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _requestedVolume = volume;
      _requestedPath = path;
      _fileLocationRequest++;
    });
  }

  void _openExternalStorage() {
    setState(() {
      _libraryOpen = false;
      _hostSetupOpen = false;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _externalDriveRequest++;
    });
  }

  void _openExplore(ExploreCategory category, {String? fileCategory}) {
    if (fileCategory == 'Documents') {
      _openLibrary('documents');
      return;
    }
    setState(() {
      _libraryOpen = false;
      _hostSetupOpen = false;
      _musicShortcutsExpanded = false;
      PocketLinkNavigation.quickShortcutsOpen.value = false;
      _initializedTabs.add(1);
      _exploreCategory = category;
      _fileCategory = fileCategory ?? 'All';
      _selectedIndex = 1;
    });
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
    final parsedServerHost = Uri.tryParse(widget.api.baseUrl)?.host;
    final serverHost = parsedServerHost == null || parsedServerHost.isEmpty
        ? widget.api.baseUrl
        : parsedServerHost;
    final drawerServerName = widget.serverName?.trim().isNotEmpty == true
        ? widget.serverName!.trim()
        : serverHost;
    final pages = [
      HomeDashboard(
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
      if (_initializedTabs.contains(1))
        ExploreScreen(
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
          onBackHandlerChanged: _onTabBackHandlerChanged,
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
                child: TweenAnimationBuilder<double>(
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
                  child: IndexedStack(
                    index: _hostSetupOpen ? 3 : (_libraryOpen ? pages.length : _selectedIndex),
                    children: [...pages, _libraryPage ?? const SizedBox.shrink()],
                  ),
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
                  child: FloatingNavigationDock(
                    order: AppSettings.instance.navigationOrder,
                    visibleItems: AppSettings.instance.visibleNavigationItems,
                    selectedIndex: _selectedIndex,
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
            ],
          ),
        ),
      ),
        ),
    );
  }
}



