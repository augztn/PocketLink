import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/navigation/pocketlink_navigation.dart';
import 'music_shortcut_menu.dart';

class FloatingNavigationDock extends StatelessWidget {
  const FloatingNavigationDock({
    required this.order,
    required this.visibleItems,
    required this.selectedIndex,
    required this.onSelect,
    required this.onBrowsePressed,
    this.isPlaying = false,
    this.hasMedia = false,
    this.isVideo = false,
    this.preview = false,
    this.musicShortcuts = const <String>[],
    this.musicShortcutsExpanded = false,
    this.musicShortcutsBottomOffset = 64,
    this.onMusicShortcutLongPress,
    this.onMusicShortcutSelected,
    this.onBrowseSwipeLeft,
    this.onBrowseSwipeRight,
    super.key,
  });

  final List<String> order;
  final Set<String> visibleItems;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onBrowsePressed;
  final bool isPlaying;
  final bool hasMedia;
  final bool isVideo;
  final bool preview;
  final List<String> musicShortcuts;
  final bool musicShortcutsExpanded;
  final double musicShortcutsBottomOffset;
  final VoidCallback? onMusicShortcutLongPress;
  final ValueChanged<String>? onMusicShortcutSelected;
  final VoidCallback? onBrowseSwipeLeft;
  final VoidCallback? onBrowseSwipeRight;

  static const _labels = <String, String>{
    'home': 'Home',
    'explore': 'Explore',
    'files': 'Files',
  };
  static const _indices = <String, int>{
    'home': 0,
    'explore': 1,
    'files': 2,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeItems = order.where(visibleItems.contains).toList(growable: false);
    final segments = <Widget>[];
    var tabGroup = <String>[];

    void addTabGroup() {
      if (tabGroup.isEmpty) return;
      final ids = List<String>.of(tabGroup);
      segments.add(
        Expanded(
          child: LiquidGlassPill(
            radius: BorderRadius.circular(32),
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (final id in ids)
                    Expanded(
                      child: _DockTab(
                        index: _indices[id]!,
                        selectedIndex: selectedIndex,
                        icon: switch (id) {
                          'home' => Icons.home_outlined,
                          'explore' => Icons.explore_outlined,
                          _ => Icons.folder_outlined,
                        },
                        activeIcon: switch (id) {
                          'home' => Icons.home_rounded,
                          'explore' => Icons.explore_rounded,
                          _ => Icons.folder_rounded,
                        },
                        label: _labels[id]!,
                        onTap: onSelect,
                        activeColor: colors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      tabGroup = <String>[];
    }

    for (final id in activeItems) {
      if (id == 'browse') {
        addTabGroup();
        segments.add(
          SizedBox(
            key: PocketLinkNavigation.musicButtonKey,
            width: 64,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (musicShortcutsExpanded && musicShortcuts.isNotEmpty)
                  Positioned(
                    right: 0,
                    bottom: musicShortcutsBottomOffset,
                    child: SizedBox(
                      width: 220,
                      child: MusicShortcutMenu(
                        shortcuts: musicShortcuts,
                        expanded: true,
                        onSelect: onMusicShortcutSelected ?? (_) {},
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity.abs() < 150) return;
                      if (velocity < 0) {
                        onBrowseSwipeLeft?.call();
                      } else {
                        onBrowseSwipeRight?.call();
                      }
                    },
                    child: LiquidGlassPill(
                      radius: BorderRadius.circular(32),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onBrowsePressed,
                          onLongPress: onMusicShortcutLongPress,
                          child: Center(
                            child: isPlaying
                                ? const _AnimatedEqualizer()
                                : Icon(
                                    hasMedia && isVideo
                                        ? Icons.play_circle_fill_rounded
                                        : Icons.music_note_rounded,
                                    color: colors.primary,
                                    size: 25,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        tabGroup.add(id);
      }
    }
    addTabGroup();

    final content = Row(
      children: [
        for (var index = 0; index < segments.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          segments[index],
        ],
      ],
    );

    if (preview) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: content,
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: content,
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
    required this.activeColor,
  });

  final int index;
  final int selectedIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final ValueChanged<int> onTap;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final selected = selectedIndex == index;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: selected ? activeColor.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: selected
                    ? Border.all(color: activeColor.withValues(alpha: 0.10))
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? activeIcon : icon, size: 21,
                    color: selected ? activeColor : colors.onSurfaceVariant),
                  const SizedBox(height: 3),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? activeColor : colors.onSurfaceVariant,
                    )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEqualizer extends StatefulWidget {
  const _AnimatedEqualizer();

  @override
  State<_AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<_AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(4, (index) {
          final phase = (_controller.value * math.pi * 2) + index * 1.15;
          final height = 9.0 + math.sin(phase).abs() * 17;
          return Container(
            width: 3.5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
