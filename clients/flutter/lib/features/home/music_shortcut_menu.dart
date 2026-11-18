import 'package:material_ui/material_ui.dart';

class MusicShortcutMenu extends StatefulWidget {
  const MusicShortcutMenu({
    required this.shortcuts,
    required this.expanded,
    required this.onSelect,
    super.key,
  });

  final List<String> shortcuts;
  final bool expanded;
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
    'search': (label: 'Search', icon: Icons.search_rounded),
    'drives': (label: 'Drives', icon: Icons.usb_rounded),
  };

  @override
  State<MusicShortcutMenu> createState() => _MusicShortcutMenuState();
}

class _MusicShortcutMenuState extends State<MusicShortcutMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    if (widget.expanded) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant MusicShortcutMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      if (widget.expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final items = widget.shortcuts.reversed.toList(growable: false);
    final menu = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _buildChip(items[index], index, items.length, reduceMotion),
        ],
      ],
    );

    if (reduceMotion) return widget.expanded ? menu : const SizedBox.shrink();
    return SizeTransition(
      sizeFactor: _controller,
      axisAlignment: 1,
      child: menu,
    );
  }

  Widget _buildChip(String id, int index, int count, bool reduceMotion) {
    final detail = MusicShortcutMenu._details[id];
    if (detail == null) return const SizedBox.shrink();
    final start = count <= 1 ? 0.0 : (index * 0.075).clamp(0.0, 0.55);
    final end = (start + 0.62).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    final chip = _ShortcutChip(
      label: detail.label,
      icon: detail.icon,
      onTap: () => widget.onSelect(id),
    );
    if (reduceMotion) return chip;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.16, 0.24),
          end: Offset.zero,
        ).animate(animation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          alignment: Alignment.centerRight,
          child: chip,
        ),
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
