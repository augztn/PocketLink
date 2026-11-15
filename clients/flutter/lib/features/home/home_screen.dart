import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'network_route_classifier.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/liquid_glass_pill.dart';
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
          bottomNavigationBar: _FloatingGlassDock(
            selectedIndex: _selectedIndex,
            isPlaying: player.isMusic && player.isPlaying,
            hasMedia: player.isActive && player.currentItem != null,
            isVideo: player.isActive && !player.isMusic,
            onSelect: _openTab,
            onMediaPressed: () => _openNowPlaying(player),
          ),
        ),
        ),
      ),
    );
  }
}

class _FloatingGlassDock extends StatelessWidget {
  const _FloatingGlassDock({
    required this.selectedIndex,
    required this.isPlaying,
    required this.hasMedia,
    required this.isVideo,
    required this.onSelect,
    required this.onMediaPressed,
  });

  final int selectedIndex;
  final bool isPlaying;
  final bool hasMedia;
  final bool isVideo;
  final ValueChanged<int> onSelect;
  final VoidCallback onMediaPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget glass({
      required Widget child,
      required BorderRadius radius,
    }) => LiquidGlassPill(radius: radius, child: child);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: glass(
                radius: BorderRadius.circular(32),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      _DockTab(index: 0, selectedIndex: selectedIndex, icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', onTap: onSelect, activeColor: colors.primary),
                      _DockTab(index: 1, selectedIndex: selectedIndex, icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: 'Explore', onTap: onSelect, activeColor: colors.primary),
                      _DockTab(index: 2, selectedIndex: selectedIndex, icon: Icons.folder_outlined, activeIcon: Icons.folder_rounded, label: 'Files', onTap: onSelect, activeColor: colors.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            glass(
              radius: BorderRadius.circular(32),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onMediaPressed,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Center(
                      child: isPlaying
                          ? const _AnimatedEqualizer()
                          : Icon(
                              hasMedia && isVideo
                                  ? Icons.play_circle_fill_rounded
                                  : Icons.music_note_rounded,
                              color: colors.primary,
                              size: 27,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
    required this.activeColor,
  });

  final int index;
  final int selectedIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final ValueChanged<int> onTap;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final selected = selectedIndex == index;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () => onTap(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected ? activeColor.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                  border: selected
                      ? Border.all(color: activeColor.withOpacity(0.10))
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(selected ? activeIcon : icon, size: 21,
                      color: selected ? activeColor : colors.onSurfaceVariant),
                    const SizedBox(height: 3),
                    Text(label, maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? activeColor : colors.onSurfaceVariant,
                      )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEqualizer extends StatefulWidget {
  const _AnimatedEqualizer();

  @override
  State<_AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<_AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(4, (index) {
          final phase = (_controller.value * math.pi * 2) + index * 1.15;
          final height = 9.0 + (math.sin(phase).abs() * 17);
          return Container(
            width: 3.5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

