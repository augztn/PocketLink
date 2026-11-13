import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../media/media_browser_screen.dart';
import '../library/library_browser_screen.dart';
import '../storage/storage_browser_screen.dart';

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
      LibraryBrowserScreen(api: widget.api, category: LibraryCategory.images),
      MediaBrowserScreen(api: widget.api, type: MediaLibraryType.music),
      MediaBrowserScreen(api: widget.api, type: MediaLibraryType.video),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _openTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_outlined),
            selectedIcon: Icon(Icons.photo),
            label: 'Images',
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note),
            label: 'Audio',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'Videos',
          ),
        ],
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({required this.api, required this.onOpenTab});

  final ServerApi api;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget category({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const Spacer(),
                Text(title, style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeServer',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Browse storage',
            onPressed: () => onOpenTab(1),
            icon: const Icon(Icons.folder_open_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_done_rounded,
                    color: colors.onPrimary, size: 30),
                const SizedBox(height: 18),
                Text('Your personal cloud',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 6),
                Text('Browse and manage files stored on your HomeServer.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onPrimary.withOpacity(0.9),
                    )),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: () => onOpenTab(1),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Browse files'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text('Categories', style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.28,
            children: [
              category(title: 'Images', subtitle: 'Photos & pictures',
                icon: Icons.photo_library_rounded, color: const Color(0xFFE59A35),
                onTap: () => onOpenTab(2)),
              category(title: 'Audio', subtitle: 'Music & recordings',
                icon: Icons.headphones_rounded, color: const Color(0xFF8B6CE8),
                onTap: () => onOpenTab(3)),
              category(title: 'Videos', subtitle: 'Movies & clips',
                icon: Icons.video_library_rounded, color: const Color(0xFF299D91),
                onTap: () => onOpenTab(4)),
              category(title: 'Documents', subtitle: 'PDF, Office & text',
                icon: Icons.description_rounded, color: const Color(0xFF4285D4),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => LibraryBrowserScreen(
                    api: api, category: LibraryCategory.documents,
                  ),
                ))),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                child: Icon(Icons.storage_rounded,
                    color: colors.onSecondaryContainer),
              ),
              title: const Text('Server storage'),
              subtitle: const Text('Browse folders, upload, download and organize files'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenTab(1),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.tertiaryContainer,
                child: Icon(Icons.usb_rounded,
                    color: colors.onTertiaryContainer),
              ),
              title: const Text('External SSDs'),
              subtitle: const Text('USB Storage 1 and USB Storage 2'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StorageBrowserScreen(api: api),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
