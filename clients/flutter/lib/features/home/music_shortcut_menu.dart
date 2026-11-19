import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';

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

  static const _details = <String, ({String label, IconData icon, Color tint})>{
    'explore': (label: 'Explore', icon: Icons.explore_rounded, tint: Color(0xFF536DFE)),
    'files': (label: 'Files', icon: Icons.folder_rounded, tint: Color(0xFF60A5FA)),
    'music': (label: 'Music', icon: Icons.music_note_rounded, tint: Color(0xFF8D72E8)),
    'videos': (label: 'Videos', icon: Icons.play_circle_fill_rounded, tint: Color(0xFF2DD4BF)),
    'photos': (label: 'Photos', icon: Icons.photo_library_rounded, tint: Color(0xFFFBBF24)),
    'documents': (label: 'Documents', icon: Icons.description_rounded, tint: Color(0xFF60A5FA)),
    'favorites': (label: 'Favorites', icon: Icons.favorite_rounded, tint: Color(0xFFFBBF24)),
    'upload': (label: 'Upload', icon: Icons.cloud_upload_rounded, tint: Color(0xFF4ADE80)),
    'search': (label: 'Search', icon: Icons.search_rounded, tint: Color(0xFF60A5FA)),
    'drives': (label: 'Drives', icon: Icons.usb_rounded, tint: Color(0xFF28B8C8)),
  };

  @override
  State<MusicShortcutMenu> createState() => _MusicShortcutMenuState();
}

class _MusicShortcutMenuState extends State<MusicShortcutMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
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
    final items = widget.shortcuts
        .where(MusicShortcutMenu._details.containsKey)
        .toList(growable: false);
    final rows = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Quick shortcuts',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            '${items.length} destinations',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      for (var start = 0; start < items.length; start += 2) ...[
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: _buildTile(
                items[start],
                start,
                items.length,
                reduceMotion,
              ),
            ),
            if (start + 1 < items.length) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildTile(
                  items[start + 1],
                  start + 1,
                  items.length,
                  reduceMotion,
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ],
    ];

    final menu = LiquidGlassPill(
      radius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );

    if (reduceMotion) {
      return widget.expanded ? menu : const SizedBox.shrink();
    }
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      axisAlignment: 1,
      child: menu,
    );
  }

  Widget _buildTile(String id, int index, int count, bool reduceMotion) {
    final detail = MusicShortcutMenu._details[id]!;
    final start = count <= 1 ? 0.0 : (index * 0.06).clamp(0.0, 0.48);
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start,
        (start + 0.66).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    final tile = _ShortcutTile(
      label: detail.label,
      icon: detail.icon,
      tint: detail.tint,
      onTap: () => widget.onSelect(id),
    );

    if (reduceMotion) return tile;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: tile,
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
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
      color: tint.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tint.withValues(alpha: 0.24)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
