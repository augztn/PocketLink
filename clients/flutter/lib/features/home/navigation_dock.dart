import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../media/now_playing_overlay_controller.dart';

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
    final progress = preview ? null : NowPlayingOverlayController.expandProgress;
    if (progress == null) return _buildDock(context, 0);

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final value = progress.value.clamp(0.0, 1.0).toDouble();
        final dockT = (value / 0.45).clamp(0.0, 1.0).toDouble();
        final dockTotalHeight = 82.0 + MediaQuery.paddingOf(context).bottom;
        return IgnorePointer(
          ignoring: value > 0.05,
          child: Transform.translate(
            offset: Offset(0, dockTotalHeight * dockT),
            child: _buildDock(context, dockT),
          ),
        );
      },
    );
  }

  Widget _buildDock(BuildContext context, double dockT) {
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
            intensity: 1.0 - dockT,
            child: Padding(
              key: const ValueKey('navigation-dock-tabs-capsule'),
              padding: const EdgeInsets.all(5),
              child: SizedBox(
                height: 54,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final innerWidth = constraints.maxWidth;
                    final slotWidth = innerWidth / ids.length;
                    final activeIndex = ids.indexWhere(
                      (id) => _indices[id] == selectedIndex,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (activeIndex >= 0)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: activeIndex * slotWidth,
                            top: 0,
                            bottom: 0,
                            width: slotWidth,
                            child: SizedBox.expand(
                              key: const ValueKey('navigation-dock-active-lens'),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            for (final id in ids)
                              Expanded(
                                child: Center(
                                  child: SizedBox(
                                    width: slotWidth,
                                    child: _DockTab(
                                      key: ValueKey('navigation-dock-tab-$id'),
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
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
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
                    glassIntensity: 1.0 - dockT,
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

class _MusicDockButton extends StatefulWidget {
  const _MusicDockButton({
    required this.preview,
    required this.glassIntensity,
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
  final double glassIntensity;
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
            intensity: widget.glassIntensity,
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
    super.key,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: () => onTap(index),
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 21,
                  color: isDark
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
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: isDark
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
