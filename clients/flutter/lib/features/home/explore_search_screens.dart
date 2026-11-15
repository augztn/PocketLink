import 'package:flutter/material.dart';
import '../../core/widgets/home_server_app_bar.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../files/documents_browser_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../media/media_browser_screen.dart';
import '../storage/storage_browser_screen.dart';

enum ExploreCategory { files, drives, photos, music, videos }

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({
    required this.api,
    required this.category,
    required this.onCategoryChanged,
    this.fileCategory = 'All',
    this.onBackAtRoot,
    super.key,
  });

  final ServerApi api;
  final ExploreCategory category;
  final ValueChanged<ExploreCategory> onCategoryChanged;
  final String fileCategory;
  final VoidCallback? onBackAtRoot;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => screen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget card({
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
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.onSurface.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: tint, size: 25),
                ),
                const Spacer(),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
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
      appBar: HomeServerAppBar(title: const Text('Explore'), onHome: onBackAtRoot),
      body: GridView.count(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 112 + MediaQuery.paddingOf(context).bottom),
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
        children: [
          card(
            title: 'Photos', subtitle: 'Your picture collection',
            icon: Icons.photo_library_rounded, tint: const Color(0xFFE5A044),
            onTap: () => _open(context, PhotoGalleryScreen(api: api)),
          ),
          card(
            title: 'Music', subtitle: 'Albums and playlists',
            icon: Icons.headphones_rounded, tint: const Color(0xFF8D72E8),
            onTap: () => _open(context, MediaBrowserScreen(api: api, type: MediaLibraryType.music)),
          ),
          card(
            title: 'Videos', subtitle: 'Movies and clips',
            icon: Icons.play_circle_fill_rounded, tint: const Color(0xFF279D91),
            onTap: () => _open(context, MediaBrowserScreen(api: api, type: MediaLibraryType.video)),
          ),
          card(
            title: 'Documents', subtitle: 'PDF, Office and text',
            icon: Icons.description_rounded, tint: const Color(0xFF4C8ED9),
            onTap: () => _open(context, DocumentsBrowserScreen(api: api)),
          ),
          card(
            title: 'Files', subtitle: 'Browse server folders',
            icon: Icons.folder_rounded, tint: const Color(0xFF7186C8),
            onTap: () => _open(context, FileManagerScreen(api: api)),
          ),
          card(
            title: 'Drives', subtitle: 'Internal & external SSDs',
            icon: Icons.usb_rounded, tint: const Color(0xFF28B8C8),
            onTap: () => _open(context, StorageBrowserScreen(api: api)),
          ),
        ],
      ),
    );
  }
}
