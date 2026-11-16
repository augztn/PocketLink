import 'package:flutter/material.dart';

import '../../core/widgets/liquid_glass_pill.dart';

class FloatingQuickShortcut extends StatefulWidget {
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
  State<FloatingQuickShortcut> createState() => _FloatingQuickShortcutState();
}

class _FloatingQuickShortcutState extends State<FloatingQuickShortcut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    if (widget.expanded) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant FloatingQuickShortcut oldWidget) {
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
    final primary = FloatingQuickShortcut._details[widget.shortcuts.first]!;
    final button = widget.useLiquidGlass
        ? Tooltip(
            message: '${primary.label} · Hold for shortcuts',
            child: LiquidGlassPill(
              radius: BorderRadius.circular(28),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onTap,
                    child: _MainButtonIcon(
                      expanded: widget.expanded,
                      primary: primary.icon,
                    ),
                  ),
                ),
              ),
            ),
          )
        : FloatingActionButton(
            heroTag: 'pocketlink-floating-shortcut',
            tooltip: '${primary.label} · Hold for shortcuts',
            onPressed: widget.onTap,
            elevation: 5,
            backgroundColor: const Color(0xFF1E2025),
            foregroundColor: Colors.white,
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: _MainButtonIcon(
              expanded: widget.expanded,
              primary: primary.icon,
            ),
          );

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final menuContent = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < widget.shortcuts.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _buildAnimatedChip(
              widget.shortcuts[widget.shortcuts.length - index - 1],
              index,
              widget.shortcuts.length,
              reduceMotion,
            ),
          ],
        ],
      ),
    );
    // Avoid a zero-sized animated render subtree in reduced-motion mode.
    // The menu is inserted at its final size so every shortcut is immediately
    // laid out and hit-testable when expanded.
    final menu = reduceMotion
        ? (widget.expanded ? menuContent : const SizedBox.shrink())
        : SizeTransition(
            sizeFactor: _controller,
            axisAlignment: 1,
            child: menuContent,
          );

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          menu,
          button,
        ],
      ),
    );
  }

  Widget _buildAnimatedChip(
    String id,
    int index,
    int count,
    bool reduceMotion,
  ) {
    final detail = FloatingQuickShortcut._details[id]!;
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
          begin: const Offset(0.16, 0.28),
          end: Offset.zero,
        ).animate(animation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(animation),
          alignment: Alignment.centerRight,
          child: chip,
        ),
      ),
    );
  }
}

class _MainButtonIcon extends StatelessWidget {
  const _MainButtonIcon({required this.expanded, required this.primary});

  final bool expanded;
  final IconData primary;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
    transitionBuilder: (child, animation) => RotationTransition(
      turns: Tween<double>(begin: -0.12, end: 0).animate(animation),
      child: ScaleTransition(scale: animation, child: child),
    ),
    child: Icon(
      expanded ? Icons.close_rounded : primary,
      key: ValueKey(expanded ? 'close' : primary),
      size: 25,
    ),
  );
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
