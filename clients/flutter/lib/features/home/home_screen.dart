import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'quick_actions_store.dart';
import 'explore_search_screens.dart';
import '../media/media_player_screen.dart';
import '../media/persistent_audio_player.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../media/media_browser_screen.dart';
import '../library/library_browser_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../storage/storage_browser_screen.dart';
import '../storage/local_storage_setup_screen.dart';
import '../transfers/transfer_manager_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, this.onReturnToConnection, super.key});

  final ServerApi api;
  final VoidCallback? onReturnToConnection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  ExploreCategory _exploreCategory = ExploreCategory.files;
  String _fileCategory = 'All';

  void _openTab(int index) => setState(() => _selectedIndex = index);

  void _openExplore(ExploreCategory category, {String? fileCategory}) {
    setState(() {
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
        builder: (_) => MediaPlayerScreen(
          api: api,
          title: item.title,
          path: item.path,
          volume: item.volume,
          isVideo: !player.isMusic,
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
      _HomeDashboard(
        api: widget.api,
        onOpenExplore: _openExplore,
        onReturnToConnection: widget.onReturnToConnection,
      ),
      ExploreScreen(
        key: const PageStorageKey<String>('homeserver-explore'),
        api: widget.api,
        category: _exploreCategory,
        fileCategory: _fileCategory,
        onBackAtRoot: () => _openTab(0),
        onCategoryChanged: (category) => setState(() {
          _exploreCategory = category;
          if (category == ExploreCategory.files) _fileCategory = 'All';
        }),
      ),
      GlobalSearchScreen(
        key: const PageStorageKey<String>('homeserver-search'),
        api: widget.api,
      ),
    ];

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) _openTab(0);
      },
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) => Scaffold(
          extendBody: true,
          body: IndexedStack(index: _selectedIndex, children: pages),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassColor = isDark
        ? colors.surface.withOpacity(0.72)
        : colors.surface.withOpacity(0.78);
    final borderColor = colors.outlineVariant.withOpacity(isDark ? 0.42 : 0.55);

    Widget glass({
      required Widget child,
      required BorderRadius radius,
      required BoxBorder border,
    }) => ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: glassColor,
            borderRadius: radius,
            border: border,
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withOpacity(isDark ? 0.24 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: colors.onSurface.withOpacity(isDark ? 0.05 : 0.035),
                blurRadius: 1,
                spreadRadius: -1,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: glass(
                radius: BorderRadius.circular(32),
                border: Border.all(color: borderColor, width: 0.8),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      _DockTab(index: 0, selectedIndex: selectedIndex, icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', onTap: onSelect, activeColor: colors.primary),
                      _DockTab(index: 1, selectedIndex: selectedIndex, icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: 'Explore', onTap: onSelect, activeColor: colors.primary),
                      _DockTab(index: 2, selectedIndex: selectedIndex, icon: Icons.search_rounded, activeIcon: Icons.search_rounded, label: 'Search', onTap: onSelect, activeColor: colors.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            glass(
              radius: BorderRadius.circular(32),
              border: Border.all(color: borderColor, width: 0.8),
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
                                  : hasMedia
                                      ? Icons.music_note_rounded
                                      : Icons.graphic_eq_rounded,
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
          final height = 9 + (math.sin(phase).abs() * 17);
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

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({
    required this.api,
    required this.onOpenExplore,
    this.onReturnToConnection,
  });

  final ServerApi api;
  final void Function(ExploreCategory category, {String? fileCategory}) onOpenExplore;
  final VoidCallback? onReturnToConnection;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> {
  bool _checking = true;
  bool? _serverOnline;
  List<StorageVolume> _volumes = const [];
  List<RecentFile> _recentFiles = const [];
  final QuickActionsStore _quickActionsStore = QuickActionsStore();
  List<String> _quickActions = List.of(QuickActionsStore.defaults);

  @override
  void initState() {
    super.initState();
    _loadQuickActions();
    _refreshStatus();
  }

  static const _quickActionDetails = <String, ({String label, IconData icon})>{
    'files': (label: 'Files', icon: Icons.folder_open_rounded),
    'photos': (label: 'Photos', icon: Icons.photo_library_rounded),
    'music': (label: 'Music', icon: Icons.headphones_rounded),
    'videos': (label: 'Videos', icon: Icons.movie_rounded),
    'drives': (label: 'Drives', icon: Icons.usb_rounded),
    'documents': (label: 'Documents', icon: Icons.description_rounded),
    'transfers': (label: 'Transfers', icon: Icons.swap_vert_rounded),
  };

  Future<void> _loadQuickActions() async {
    final actions = await _quickActionsStore.load();
    if (mounted) setState(() => _quickActions = actions);
  }

  Future<void> _editQuickActions() async {
    var draft = List<String>.of(_quickActions);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customize quick actions'),
          content: SizedBox(
            width: 420,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Drag to rearrange. Select the actions you want on Home.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: draft.length,
                    onReorder: (oldIndex, newIndex) {
                      setDialogState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = draft.removeAt(oldIndex);
                        draft.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final id = draft[index];
                      final detail = _quickActionDetails[id]!;
                      return CheckboxListTile(
                        key: ValueKey(id),
                        value: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        secondary: const Icon(Icons.drag_handle_rounded),
                        title: Text(detail.label),
                        onChanged: (checked) {
                          if (checked == false) {
                            setDialogState(() => draft.remove(id));
                          }
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                Text('Add actions', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: QuickActionsStore.available
                      .where((id) => !draft.contains(id))
                      .map((id) => ActionChip(
                            avatar: Icon(_quickActionDetails[id]!.icon, size: 17),
                            label: Text(_quickActionDetails[id]!.label),
                            onPressed: () => setDialogState(() => draft.add(id)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => setDialogState(
                () => draft = List.of(QuickActionsStore.defaults),
              ),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: draft.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _quickActionsStore.save(result);
    if (mounted) setState(() => _quickActions = result);
  }

  void _runQuickAction(String id) {
    switch (id) {
      case 'files':
        widget.onOpenExplore(ExploreCategory.files);
        return;
      case 'photos':
        widget.onOpenExplore(ExploreCategory.photos);
        return;
      case 'music':
        widget.onOpenExplore(ExploreCategory.music);
        return;
      case 'videos':
        widget.onOpenExplore(ExploreCategory.videos);
        return;
      case 'drives':
        widget.onOpenExplore(ExploreCategory.drives);
        return;
      case 'documents':
        widget.onOpenExplore(ExploreCategory.files, fileCategory: 'Documents');
        return;
      case 'transfers':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const TransferManagerScreen(),
        ));
        return;
    }
  }

  Future<void> _refreshStatus() async {
    if (mounted) setState(() => _checking = true);
    var online = false;
    var volumes = <StorageVolume>[];
    try {
      await widget.api.authenticate();
      online = true;
      try {
        volumes = await widget.api.listStorageVolumes();
      } catch (_) {
        // The server can be reachable even when the optional volume endpoint fails.
      }
      try {
        final recentFiles = await widget.api.listRecentFiles(volumes: volumes);
        if (mounted) setState(() => _recentFiles = recentFiles);
      } catch (_) {
        // A recent-file scan failure must not mark a reachable server as offline.
      }
    } catch (_) {
      online = false;
    }
    if (!mounted) return;
    setState(() {
      _serverOnline = online;
      _volumes = volumes;
      _checking = false;
    });
  }

  void _openDocuments() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LibraryBrowserScreen(
        api: widget.api,
        category: LibraryCategory.documents,
      ),
    ));
  }

  void _openStorage() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StorageBrowserScreen(api: widget.api),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final availableVolumes = _volumes.where((volume) => volume.available).length;

    Widget sectionTitle(String title, {String? action, VoidCallback? onAction}) {
      return Row(
        children: [
          Expanded(
            child: Text(title, style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            )),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ],
      );
    }

    Widget quickAction(IconData icon, String label, VoidCallback onTap) {
      return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 23, color: colors.primary),
                const SizedBox(height: 8),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    Widget category({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color tint,
      required VoidCallback onTap,
    }) {
      return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tint.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: tint, size: 25),
                ),
                const Spacer(),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                )),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.surface,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.cloud_rounded, color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 14),
                    Text('HomeServer', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('Storage & locations', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
                child: Text('STORAGE', style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1,
                )),
              ),
              ListTile(
                leading: const Icon(Icons.phone_android_rounded),
                title: const Text('Internal storage'),
                subtitle: const Text('Browse server folders'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenExplore(ExploreCategory.files);
                },
              ),
              ListTile(
                leading: const Icon(Icons.usb_rounded),
                title: const Text('USB & external drives'),
                subtitle: Text(_checking ? 'Checking connected drives…' : '$availableVolumes of ${_volumes.length} available'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenExplore(ExploreCategory.drives);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_to_drive_rounded),
                title: const Text('Connect a drive'),
                subtitle: const Text('Set up USB / SSD / OTG access'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const LocalStorageSetupScreen(),
                  ));
                },
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.switch_account_rounded),
                title: const Text('Connection / Switch server'),
                subtitle: const Text('Return to the server login screen'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onReturnToConnection?.call();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                child: Text('TOOLS', style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1,
                )),
              ),
              ListTile(
                leading: const Icon(Icons.swap_vert_rounded),
                title: const Text('Transfers'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const TransferManagerScreen(),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HomeServer', style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            )),
            Text('Your private space', style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            )),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Transfers',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const TransferManagerScreen(),
            )),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
          IconButton(
            tooltip: 'Refresh server status',
            onPressed: _checking ? null : _refreshStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, 8, 18, 104 + MediaQuery.paddingOf(context).bottom),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, 0.72)!],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colors.onPrimary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.cloud_done_rounded, color: colors.onPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: colors.onPrimary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _checking ? colors.onPrimary : (_serverOnline == true ? const Color(0xFF8EF0B0) : const Color(0xFFFFB4AB)),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _checking ? 'Checking' : (_serverOnline == true ? 'Server online' : 'Server offline'),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Text('Your files.\nYour own cloud.', style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.onPrimary,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                  )),
                  const SizedBox(height: 9),
                  Text('Access your photos, music, videos and files from anywhere.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onPrimary.withOpacity(0.86),
                      height: 1.4,
                    )),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.onPrimary,
                      foregroundColor: colors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                    ),
                    onPressed: () => widget.onOpenExplore(ExploreCategory.files),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Browse files', style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 27),
            sectionTitle(
              'Quick actions',
              action: 'Edit',
              onAction: _editQuickActions,
            ),
            const SizedBox(height: 12),
            if (_quickActions.isEmpty)
              OutlinedButton.icon(
                onPressed: _editQuickActions,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add quick actions'),
              )
            else
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                childAspectRatio: 0.88,
                children: _quickActions.map((id) {
                  final detail = _quickActionDetails[id]!;
                  return quickAction(
                    detail.icon,
                    detail.label,
                    () => _runQuickAction(id),
                  );
                }).toList(),
              ),
            const SizedBox(height: 27),
            sectionTitle('Your library'),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.24,
              children: [
                category(
                  title: 'Photos',
                  subtitle: 'Your picture collection',
                  icon: Icons.photo_rounded,
                  tint: const Color(0xFFE5A044),
                  onTap: () => widget.onOpenExplore(ExploreCategory.photos),
                ),
                category(
                  title: 'Music',
                  subtitle: 'Albums and playlists',
                  icon: Icons.headphones_rounded,
                  tint: const Color(0xFF8D72E8),
                  onTap: () => widget.onOpenExplore(ExploreCategory.music),
                ),
                category(
                  title: 'Videos',
                  subtitle: 'Movies and clips',
                  icon: Icons.play_circle_fill_rounded,
                  tint: const Color(0xFF279D91),
                  onTap: () => widget.onOpenExplore(ExploreCategory.videos),
                ),
                category(
                  title: 'Documents',
                  subtitle: 'PDF, Office and text',
                  icon: Icons.description_rounded,
                  tint: const Color(0xFF4C8ED9),
                  onTap: () => widget.onOpenExplore(ExploreCategory.files, fileCategory: 'Documents'),
                ),
              ],
            ),
            const SizedBox(height: 27),
            sectionTitle(
              'Recent files',
              action: 'Browse',
              onAction: () => widget.onOpenTab(1),
            ),
            const SizedBox(height: 10),
            if (_recentFiles.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: colors.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _checking
                            ? 'Checking your folders for recent files…'
                            : 'No recent files found in the scanned folders.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var index = 0; index < _recentFiles.length; index++) ...[
                      if (index > 0) const Divider(height: 1, indent: 68),
                      ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            _recentFiles[index].file.name.contains('.')
                                ? Icons.insert_drive_file_outlined
                                : Icons.folder_outlined,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                        title: Text(
                          _recentFiles[index].file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${_recentFiles[index].volumeName} · ${_recentFiles[index].parentPath.isEmpty ? 'Root' : _recentFiles[index].parentPath}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          final recent = _recentFiles[index];
                          if (recent.volume == null) {
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => FileManagerScreen(
                                api: widget.api,
                                initialPath: recent.parentPath,
                              ),
                            ));
                          } else {
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => StorageBrowserScreen(
                                api: widget.api,
                                initialVolume: recent.volume,
                                initialPath: recent.parentPath,
                              ),
                            ));
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 27),

          ],
        ),
      ),
    );
  }
}
