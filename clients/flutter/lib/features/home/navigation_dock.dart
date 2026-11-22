import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/pocketlink_scaffold.dart';

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
    this.musicShortcutsExpanded = false,
    this.onMusicShortcutLongPress,
    this.onMusicShortcutDismissed,
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
  final bool musicShortcutsExpanded;
  final VoidCallback? onMusicShortcutLongPress;
  final VoidCallback? onMusicShortcutDismissed;
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
            refractive: true,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: SizedBox(
                height: 54,
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
                      ),
                    ),
                  ],
                ),
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
            key: preview ? null : PocketLinkNavigation.musicButtonKey,
            width: 64,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                 Positioned.fill(
                  child: _MusicDockButton(
                    preview: preview,
                    isPlaying: isPlaying,
                    hasMedia: hasMedia,
                    isVideo: isVideo,
                    expanded: musicShortcutsExpanded,
                    onTap: musicShortcutsExpanded
                        ? (onMusicShortcutDismissed ?? () {})
                        : onBrowsePressed,
                    onLongPress: onMusicShortcutLongPress,
                    onSwipeNext: onBrowseSwipeLeft,
                    onSwipePrevious: onBrowseSwipeRight,
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
          if (index > 0) const SizedBox(width: 12),
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
      left: false,
      right: false,
      child: Padding(
        padding: PocketLinkHorizontalGutter.padding(context).copyWith(
          top: 8,
          bottom: 12,
        ),
        child: content,
      ),
    );
  }
}

class _MusicDockButton extends StatefulWidget {
  const _MusicDockButton({
    required this.preview,
    required this.isPlaying,
    required this.hasMedia,
    required this.isVideo,
    required this.expanded,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipeNext,
    required this.onSwipePrevious,
  });

  final bool preview;
  final bool isPlaying;
  final bool hasMedia;
  final bool isVideo;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipeNext;
  final VoidCallback? onSwipePrevious;

  @override
  State<_MusicDockButton> createState() => _MusicDockButtonState();
}

class _MusicDockButtonState extends State<_MusicDockButton> {
  double _dragOffset = 0;
  double _totalDrag = 0;
  bool _dragging = false;

  int get _dragDirection {
    if (_dragOffset < -8) return -1;
    if (_dragOffset > 8) return 1;
    return 0;
  }

  void _onDragStart(DragStartDetails details) {
    if (widget.preview) return;
    setState(() {
      _dragging = true;
      _dragOffset = 0;
      _totalDrag = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.preview) return;
    setState(() {
      _totalDrag += details.delta.dx;
      _dragOffset = (_dragOffset + details.delta.dx * 0.55)
          .clamp(-34.0, 34.0)
          .toDouble();
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.preview) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final next = _totalDrag < -44 || (_totalDrag < -18 && velocity < -520);
    final previous = _totalDrag > 44 || (_totalDrag > 18 && velocity > 520);

    setState(() {
      _dragging = false;
      _dragOffset = 0;
      _totalDrag = 0;
    });

    if (next) {
      HapticFeedback.selectionClick();
      widget.onSwipeNext?.call();
    } else if (previous) {
      HapticFeedback.selectionClick();
      widget.onSwipePrevious?.call();
    }
  }

  void _onDragCancel() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragOffset = 0;
      _totalDrag = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final direction = _dragDirection;
    final iconKey = widget.expanded
        ? 'shortcuts'
        : direction < 0
            ? 'next'
            : direction > 0
                ? 'previous'
                : widget.isPlaying
                    ? 'playing'
                    : widget.hasMedia && widget.isVideo
                        ? 'video'
                        : 'music';

    return Semantics(
      button: true,
      label: 'Music button. Tap to open Now Playing, swipe to change tracks, hold for shortcuts.',
      child: AnimatedContainer(
        duration: _dragging || reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        transform: Matrix4.translationValues(_dragOffset, 0, 0),

        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.preview ? null : _onDragStart,
          onHorizontalDragUpdate: widget.preview ? null : _onDragUpdate,
          onHorizontalDragEnd: widget.preview ? null : _onDragEnd,
          onHorizontalDragCancel: widget.preview ? null : _onDragCancel,
          child: LiquidGlassPill(
            radius: BorderRadius.circular(32),
            refractive: true,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.preview ? null : widget.onTap,
                onLongPress: widget.preview || widget.onLongPress == null
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        widget.onLongPress!.call();
                      },
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      reverseDuration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final offset = direction < 0
                            ? const Offset(0.32, 0)
                            : const Offset(-0.32, 0);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: offset,
                              end: Offset.zero,
                            ).animate(animation),
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.72, end: 1)
                                  .animate(animation),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: switch (iconKey) {
                        'shortcuts' => Icon(
                            Icons.keyboard_arrow_down_rounded,
                            key: const ValueKey('shortcuts'),
                            color: colors.primary,
                            size: 29,
                          ),
                        'next' => Icon(
                            Icons.skip_next_rounded,
                            key: const ValueKey('next'),
                            color: colors.tertiary,
                            size: 29,
                          ),
                        'previous' => Icon(
                            Icons.skip_previous_rounded,
                            key: const ValueKey('previous'),
                            color: colors.tertiary,
                            size: 29,
                          ),
                        'playing' => _AnimatedEqualizer(
                            key: const ValueKey('playing'),
                            color: colors.primary,
                          ),
                        'video' => Icon(
                            Icons.play_circle_fill_rounded,
                            key: const ValueKey('video'),
                            color: colors.primary,
                            size: 26,
                          ),
                        _ => Icon(
                            Icons.music_note_rounded,
                            key: const ValueKey('music'),
                            color: colors.primary,
                            size: 25,
                          ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
  });

  final int index;
  final int selectedIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final selected = selectedIndex == index;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              gradient: selected
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.14),
                            Colors.white.withValues(alpha: 0.07),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.alphaBlend(
                              const Color(0x1A536DFE),
                              Colors.white.withValues(alpha: 0.90),
                            ),
                            Color.alphaBlend(
                              const Color(0x1A536DFE),
                              Colors.white.withValues(alpha: 0.90),
                            ),
                          ],
                        ))
                  : null,
              borderRadius: BorderRadius.circular(25),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.22)
                          : const Color(0xFF536DFE)
                              .withValues(alpha: 0.25),
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 21,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: selected ? 1 : 0.65)
                      : selected
                          ? const Color(0xFF4355E8)
                          : const Color(0xFF475569),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: selected ? 1 : 0.65)
                            : selected
                                ? const Color(0xFF4355E8)
                                : const Color(0xFF475569),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEqualizer extends StatefulWidget {
  const _AnimatedEqualizer({super.key, required this.color});

  final Color color;

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
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
