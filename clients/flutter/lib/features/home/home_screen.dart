import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import 'navigation_dock.dart';
import 'explore_search_screens.dart';
import 'home_dashboard.dart';
import '../media/media_player_screen.dart';
import '../media/now_playing_screen.dart';
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
  String? _requestedVolume;
  String _requestedPath = '';

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
          requestedVolume: _requestedVolume,
          requestedPath: _requestedPath,
        )
      else
        const SizedBox.shrink(),
    ];

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) _openTab(0);
      },
      child: AnimatedBuilder(
        animation: AppSettings.instance,
        builder: (context, __) => AnimatedBuilder(
        animation: player,
        builder: (context, _) => Scaffold(
          extendBody: true,
          body: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 300) return;
              final nextIndex = velocity < 0
                  ? (_selectedIndex + 1).clamp(0, pages.length - 1)
                  : (_selectedIndex - 1).clamp(0, pages.length - 1);
              if (nextIndex != _selectedIndex) _openTab(nextIndex);
            },
            child: IndexedStack(index: _selectedIndex, children: pages),
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

