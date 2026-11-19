import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';

/// Navigation drawer owned by HomeScreen's outer Scaffold so its scrim covers
/// the bottom navigation dock and the app-level media overlay.
class PocketLinkHomeDrawer extends StatelessWidget {
  const PocketLinkHomeDrawer({
    required this.serverName,
    required this.routeLabel,
    required this.onOpenLibrary,
    required this.onOpenFiles,
    required this.onOpenDrives,
    required this.onConnectDrive,
    required this.onOpenTransfers,
    required this.onOpenSettings,
    this.onSwitchServer,
    super.key,
  });

  final String serverName;
  final String routeLabel;
  final ValueChanged<String> onOpenLibrary;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenDrives;
  final VoidCallback onConnectDrive;
  final VoidCallback onOpenTransfers;
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
      child: SafeArea(
        bottom: true,
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: [
                  _sectionLabel(context, 'QUICK LIBRARIES'),
                  const SizedBox(height: 9),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 2.2,
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
                    leading: const Icon(Icons.folder_open_rounded),
                    title: const Text('Files'),
                    subtitle: const Text('Browse server folders'),
                    onTap: () => _closeThen(context, onOpenFiles),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.usb_rounded),
                    title: const Text('Drives'),
                    subtitle: const Text('Internal and external storage'),
                    onTap: () => _closeThen(context, onOpenDrives),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_to_drive_rounded),
                    title: const Text('Connect a drive'),
                    subtitle: const Text('USB, SSD and OTG setup'),
                    onTap: () => _closeThen(context, onConnectDrive),
                  ),
                  const Divider(height: 22),
                  _sectionLabel(context, 'TOOLS'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.swap_vert_rounded),
                    title: const Text('Transfers'),
                    onTap: () => _closeThen(context, onOpenTransfers),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_rounded),
                    title: const Text('Settings'),
                    onTap: () => _closeThen(context, onOpenSettings),
                  ),
                  if (onSwitchServer != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.switch_account_rounded),
                      title: const Text('Switch server'),
                      subtitle: const Text('Return to server connection'),
                      onTap: () => _closeThen(context, onSwitchServer!),
                    ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: AppSettings.instance,
              builder: (context, _) {
                final settings = AppSettings.instance;
                final isDark = settings.themeMode == ThemeMode.dark;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
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
                      Wrap(
                        spacing: 7,
                        children: [
                          ChoiceChip(
                            label: const Text('Light'),
                            selected: settings.themeMode == ThemeMode.light,
                            onSelected: (selected) {
                              if (selected) {
                                settings.setThemeMode(ThemeMode.light);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Dark'),
                            selected: isDark && !settings.amoled,
                            onSelected: (selected) {
                              if (selected) {
                                settings.setThemeMode(ThemeMode.dark);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('AMOLED'),
                            selected: settings.amoled,
                            onSelected: (selected) {
                              if (selected) settings.setAmoled(true);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
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
