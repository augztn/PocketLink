import 'package:flutter/material.dart';

import '../../core/widgets/liquid_glass_pill.dart';

class FloatingQuickShortcut extends StatelessWidget {
  const FloatingQuickShortcut({
    required this.shortcuts,
    required this.expanded,
    required this.useLiquidGlass,
    required this.onTap,
    required this.onLongPress,
    required this.onSelect,
    super.key,
  });

  final List<String> shortcuts;
  final bool expanded;
  final bool useLiquidGlass;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onSelect;

  static const _details = <String, ({String label, IconData icon})>{
    'explore': (label: 'Explore', icon: Icons.explore_rounded),
    'files': (label: 'Files', icon: Icons.folder_rounded),
    'music': (label: 'Music', icon: Icons.music_note_rounded),
    'videos': (label: 'Videos', icon: Icons.play_circle_fill_rounded),
    'photos': (label: 'Photos', icon: Icons.photo_library_rounded),
    'documents': (label: 'Documents', icon: Icons.description_rounded),
    'favorites': (label: 'Favorites', icon: Icons.favorite_rounded),
    'upload': (label: 'Upload', icon: Icons.cloud_upload_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final primary = _details[shortcuts.first]!;
    final button = useLiquidGlass
        ? LiquidGlassPill(
            radius: BorderRadius.circular(28),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Icon(primary.icon, color: Theme.of(context).colorScheme.primary, size: 25),
                ),
              ),
            ),
          )
        : FloatingActionButton(
            heroTag: 'pocketlink-floating-shortcut',
            tooltip: '${primary.label} · Hold for shortcuts',
            onPressed: onTap,
            elevation: 5,
            backgroundColor: const Color(0xFF1E2025),
            foregroundColor: Colors.white,
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(primary.icon, size: 25),
          );

    return GestureDetector(
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomRight,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final id in shortcuts.reversed) ...[
                          if (id != shortcuts.last) const SizedBox(height: 8),
                          _ShortcutChip(
                            label: _details[id]!.label,
                            icon: _details[id]!.icon,
                            onTap: () => onSelect(id),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          button,
        ],
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF1E2025),
      elevation: 4,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42, minWidth: 112),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 9),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
