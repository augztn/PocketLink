import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../media/media_browser_screen.dart';
import '../library/library_browser_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../storage/storage_browser_screen.dart';
import '../storage/local_storage_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, super.key});

  final ServerApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  void _openTab(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeDashboard(api: widget.api, onOpenTab: _openTab),
      FileManagerScreen(api: widget.api),
      PhotoGalleryScreen(api: widget.api),
      MediaBrowserScreen(api: widget.api, type: MediaLibraryType.music),
      MediaBrowserScreen(api: widget.api, type: MediaLibraryType.video),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _openTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.photo_outlined), selectedIcon: Icon(Icons.photo), label: 'Images'),
          NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Audio'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Videos'),
        ],
      ),
    );
  }
}

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({required this.api, required this.onOpenTab});

  final ServerApi api;
  final ValueChanged<int> onOpenTab;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> {
  bool _checking = true;
  bool? _serverOnline;
  List<StorageVolume> _volumes = const [];
  List<RecentFile> _recentFiles = const [];

  @override
  void initState() {
    super.initState();
    _refreshStatus();
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
      appBar: AppBar(
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
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
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
                    onPressed: () => widget.onOpenTab(1),
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
            sectionTitle('Quick actions'),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 9,
              childAspectRatio: 0.88,
              children: [
                quickAction(Icons.folder_open_rounded, 'Files', () => widget.onOpenTab(1)),
                quickAction(Icons.photo_library_rounded, 'Photos', () => widget.onOpenTab(2)),
                quickAction(Icons.headphones_rounded, 'Music', () => widget.onOpenTab(3)),
                quickAction(Icons.usb_rounded, 'Drives', _openStorage),
              ],
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
                  onTap: () => widget.onOpenTab(2),
                ),
                category(
                  title: 'Music',
                  subtitle: 'Albums and playlists',
                  icon: Icons.headphones_rounded,
                  tint: const Color(0xFF8D72E8),
                  onTap: () => widget.onOpenTab(3),
                ),
                category(
                  title: 'Videos',
                  subtitle: 'Movies and clips',
                  icon: Icons.play_circle_fill_rounded,
                  tint: const Color(0xFF279D91),
                  onTap: () => widget.onOpenTab(4),
                ),
                category(
                  title: 'Documents',
                  subtitle: 'PDF, Office and text',
                  icon: Icons.description_rounded,
                  tint: const Color(0xFF4C8ED9),
                  onTap: _openDocuments,
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
            sectionTitle('Storage', action: 'Open', onAction: _openStorage),
            const SizedBox(height: 12),
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _openStorage,
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.secondaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.phone_android_rounded, color: colors.onSecondaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Internal storage', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text('Browse server folders', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Divider(height: 1),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.tertiaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.storage_rounded, color: colors.onTertiaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('USB / external drives', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  _checking ? 'Checking connected volumes…' : 'Available: $availableVolumes of ${_volumes.length}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LocalStorageSetupScreen(),
                )),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.add_to_drive_rounded, color: colors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Connect a USB drive', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            Text('Set up access to an external SSD or OTG drive',
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
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
