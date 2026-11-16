import 'package:flutter/material.dart';
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
  final Set<int> _initializedTabs = {0};
  ExploreCategory _exploreCategory = ExploreCategory.files;
  String _fileCategory = 'All';
  int _externalDriveRequest = 0;
  int _fileLocationRequest = 0;
  int _uploadRequest = 0;
  bool _quickShortcutsExpanded = false;
  String? _requestedVolume;
  String _requestedPath = '';

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_navigationSettingsChanged);
  }

  void _navigationSettingsChanged() {
    final settings = AppSettings.instance;
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
    _initializedTabs.add(index);
    _selectedIndex = index;
  });

  void _openFileLocation(String? volume, String path) {
    setState(() {
      _initializedTabs.add(2);
      _selectedIndex = 2;
      _requestedVolume = volume;
      _requestedPath = path;
      _fileLocationRequest++;
    });
  }

  void _openExternalStorage() {
    setState(() {
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
      case 'files':
        _openTab(2);
      case 'music':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowserScreen(
            api: widget.api,
            type: MediaLibraryType.music,
          ),
        ));
      case 'videos':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowserScreen(
            api: widget.api,
            type: MediaLibraryType.video,
          ),
        ));
      case 'photos':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PhotoGalleryScreen(api: widget.api),
        ));
      case 'documents':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DocumentsBrowserScreen(api: widget.api),
        ));
      case 'favorites':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PhotoGalleryScreen(api: widget.api, initialTab: 2),
        ));
      case 'upload':
        setState(() {
          _initializedTabs.add(2);
          _selectedIndex = 2;
          _uploadRequest++;
        });
    }
  }

  void _expandFloatingShortcuts() {
    HapticFeedback.lightImpact();
    setState(() => _quickShortcutsExpanded = true);
  }

  void _openNowPlaying(PersistentAudioPlayer player) {
    final item = player.currentItem;
    final api = player.api;
    if (player.isActive && item != null && api != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
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
        onOpenFileLocation: _openFileLocation,
        onReturnToConnection: widget.onReturnToConnection,
      ),
      if (_initializedTabs.contains(1))
        ExploreScreen(
          key: const PageStorageKey<String>('homeserver-explore'),
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
          key: PageStorageKey<String>('homeserver-files-${widget.api.baseUrl}'),
          api: widget.api,
          isActive: true,
          onBackAtRoot: () => _openTab(0),
          externalDriveRequest: _externalDriveRequest,
          locationRequest: _fileLocationRequest,
          uploadRequest: _uploadRequest,
          requestedVolume: _requestedVolume,
          requestedPath: _requestedPath,
        )
      else
        const SizedBox.shrink(),
    ];

    return PopScope(
      canPop: _selectedIndex == 0 && !_quickShortcutsExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_quickShortcutsExpanded) {
          setState(() => _quickShortcutsExpanded = false);
        } else if (_selectedIndex != 0) {
          _openTab(0);
        }
      },
      child: AnimatedBuilder(
        animation: AppSettings.instance,
        builder: (context, __) => AnimatedBuilder(
        animation: player,
        builder: (context, _) => Scaffold(
          extendBody: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onHorizontalDragEnd: (details) {
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
                child: IndexedStack(index: _selectedIndex, children: pages),
              ),
              if (AppSettings.instance.floatingShortcutEnabled && _quickShortcutsExpanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _quickShortcutsExpanded = false),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (AppSettings.instance.floatingShortcutEnabled)
                Positioned(
                  right: 16,
                  bottom: 90 + MediaQuery.paddingOf(context).bottom,
                  child: FloatingQuickShortcut(
                    shortcuts: AppSettings.instance.floatingShortcuts,
                    expanded: _quickShortcutsExpanded,
                    useLiquidGlass: AppSettings.instance.useLiquidGlass,
                    onTap: () => _openFloatingShortcut(
                      AppSettings.instance.floatingShortcuts.first,
                    ),
                    onLongPress: _expandFloatingShortcuts,
                    onSelect: _openFloatingShortcut,
                  ),
                ),
            ],
          ),
          bottomNavigationBar: FloatingNavigationDock(
            order: AppSettings.instance.navigationOrder,
            visibleItems: AppSettings.instance.visibleNavigationItems,
            selectedIndex: _selectedIndex,
            isPlaying: player.isMusic && player.isPlaying,
            hasMedia: player.isActive && player.currentItem != null,
            isVideo: player.isActive && !player.isMusic,
            onSelect: _openTab,
            onBrowsePressed: () => _openNowPlaying(player),
          ),
        ),
        ),
      ),
    );
  }
}

