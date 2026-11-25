import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/feathered_glass_header.dart';
import '../../../core/widgets/smoked_glass_popover_menu.dart';

class MusicMoreActionsMenu extends StatelessWidget {
  const MusicMoreActionsMenu({
    required this.onShuffle,
    required this.onSelect,
    required this.onScan,
    required this.onSettings,
    required this.onHome,
    super.key,
  });

  final VoidCallback? onShuffle;
  final VoidCallback onSelect;
  final VoidCallback onScan;
  final VoidCallback onSettings;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return SmokedGlassPopoverMenu<String>(
      tooltip: 'More music actions',
      items: [
        const SmokedGlassPopoverMenuItem(
          value: 'shuffle',
          label: 'Shuffle all',
          icon: Icons.shuffle_rounded,
        ),
        const SmokedGlassPopoverMenuItem(
          value: 'select',
          label: 'Select tracks',
          icon: Icons.checklist_rounded,
        ),
        const SmokedGlassPopoverMenuItem(
          value: 'scan',
          label: 'Scan library',
          icon: Icons.refresh_rounded,
        ),
        const SmokedGlassPopoverMenuItem(
          value: 'settings',
          label: 'Settings',
          icon: Icons.settings_rounded,
          dividerBefore: true,
        ),
        const SmokedGlassPopoverMenuItem(
          value: 'home',
          label: 'Return to Home',
          icon: Icons.home_rounded,
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'shuffle':
            onShuffle?.call();
          case 'select':
            onSelect();
          case 'scan':
            onScan();
          case 'settings':
            onSettings();
          case 'home':
            onHome();
        }
      },
      child: const GlassCircleButton(
        tooltip: 'Open more music actions',
        onPressed: null,
        child: Icon(Icons.more_vert_rounded, size: 18),
      ),
    );
  }
}
