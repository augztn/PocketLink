import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';
import '../downloads/download_manager_service.dart';

/// Navigation drawer owned by HomeScreen's outer Scaffold so its scrim covers
/// the bottom navigation dock and the app-level media overlay.
class PocketLinkHomeDrawer extends StatelessWidget {
  const PocketLinkHomeDrawer({
    required this.serverName,
    required this.routeLabel,
    required this.onOpenLibrary,
    required this.onOpenFiles,
    required this.onConnectDrive,
    required this.onOpenTransfers,
    required this.onOpenDownloads,
    required this.onOpenSettings,
    this.onSwitchServer,
    super.key,
  });

  final String serverName;
  final String routeLabel;
  final ValueChanged<String> onOpenLibrary;
  final VoidCallback onOpenFiles;
  final VoidCallback onConnectDrive;
  final VoidCallback onOpenTransfers;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenSettings;
  final VoidCallback? onSwitchServer;

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compactServerName = serverName.trim().isEmpty
        ? 'Connected server'
        : serverName.trim();

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.88,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 8, 0, MediaQuery.paddingOf(context).bottom + 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border(top: BorderSide(
            color: Colors.white.withValues(alpha: 0.24),
            width: 1,
          )),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: ColoredBox(
              color: const Color(0xFF1C1E24).withValues(alpha: 0.72),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.cloud_rounded,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PocketLink',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                compactServerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        const _DrawerStatusPill(
                          label: 'Connected',
                          icon: Icons.check_circle_rounded,
                          foreground: Color(0xFF16865B),
                          background: Color(0x2210B981),
                        ),
                        _DrawerStatusPill(
                          label: routeLabel,
                          icon: routeLabel == 'Tailscale'
                              ? Icons.shield_rounded
                              : Icons.route_rounded,
                          foreground: colors.primary,
                          background: colors.primary.withValues(alpha: 0.10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 20),
                children: [
                  _sectionLabel(context, 'QUICK LIBRARIES'),
                  const SizedBox(height: 9),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 1.65,
                    children: [
                      _DrawerLibraryTile(
                        label: 'Music',
                        icon: Icons.music_note_rounded,
                        tint: const Color(0xFF9B7CFF),
                        onTap: () => _closeThen(
                          context,
                          () => onOpenLibrary('music'),
                        ),
                      ),
                      _DrawerLibraryTile(
                        label: 'Videos',
                        icon: Icons.movie_rounded,
                        tint: const Color(0xFF2FAFC1),
                        onTap: () => _closeThen(
                          context,
                          () => onOpenLibrary('videos'),
                        ),
                      ),
                      _DrawerLibraryTile(
                        label: 'Photos',
                        icon: Icons.photo_library_rounded,
                        tint: const Color(0xFFEA8B62),
                        onTap: () => _closeThen(
                          context,
                          () => onOpenLibrary('photos'),
                        ),
                      ),
                      _DrawerLibraryTile(
                        label: 'Documents',
                        icon: Icons.description_rounded,
                        tint: const Color(0xFF5D8FEF),
                        onTap: () => _closeThen(
                          context,
                          () => onOpenLibrary('documents'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(context, 'STORAGE & HOST'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 46,
                    leading: _drawerIcon(Icons.folder_open_rounded),
                    title: const Text('Files'),
                    subtitle: const Text('Browse server folders and drives'),
                    onTap: () => _closeThen(context, onOpenFiles),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _drawerIcon(Icons.add_to_drive_rounded),
                    minTileHeight: 46,
                    title: const Text('Connect a drive'),
                    subtitle: const Text('USB, SSD and OTG setup'),
                    onTap: () => _closeThen(context, onConnectDrive),
                  ),
                  const Divider(height: 22),
                  _sectionLabel(context, 'TOOLS'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 46,
                    leading: _drawerIcon(Icons.swap_vert_rounded),
                    title: const Text('Transfers'),
                    onTap: () => _closeThen(context, onOpenTransfers),
                  ),
                  AnimatedBuilder(
                    animation: DownloadManagerService.instance,
                    builder: (context, _) {
                      final active = DownloadManagerService.instance.activeCount;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: 46,
                        leading: _drawerIcon(Icons.download_rounded),
                        title: Row(
                          children: [
                            const Expanded(child: Text('Downloads')),
                            if (active > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '$active active',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: () => _closeThen(context, onOpenDownloads),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 46,
                    leading: _drawerIcon(Icons.settings_rounded),
                    title: const Text('Settings'),
                    onTap: () => _closeThen(context, onOpenSettings),
                  ),
                  if (onSwitchServer != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _drawerIcon(Icons.switch_account_rounded),
                      title: const Text('Switch server'),
                      subtitle: const Text('Return to server connection'),
                      onTap: () => _closeThen(context, onSwitchServer!),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Divider(height: 1),
                  ),
                  AnimatedBuilder(
                    animation: AppSettings.instance,
                    builder: (context, _) {
                      final settings = AppSettings.instance;
                      final isDark = settings.themeMode == ThemeMode.dark;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'APPEARANCE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                              ),
                              child: Row(
                                children: [
                                  _ThemeSegment(label: 'Light', selected: settings.themeMode == ThemeMode.light,
                                    onTap: () => settings.setThemeMode(ThemeMode.light)),
                                  _ThemeSegment(label: 'Dark', selected: isDark && !settings.amoled,
                                    onTap: () => settings.setThemeMode(ThemeMode.dark)),
                                  _ThemeSegment(label: 'AMOLED', selected: settings.amoled,
                                    onTap: () => settings.setAmoled(true)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
),
  ),
);
  }

  Widget _drawerIcon(IconData icon) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 19),
      );

  Widget _sectionLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.05,
              ),
        ),
      );
}

class _DrawerLibraryTile extends StatelessWidget {
  const _DrawerLibraryTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white.withValues(alpha: isDark ? 0.045 : 0.48),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: tint, size: 19),
              ),
              const SizedBox(height: 7),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('Open library', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerStatusPill extends StatelessWidget {
  const _DrawerStatusPill({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}
