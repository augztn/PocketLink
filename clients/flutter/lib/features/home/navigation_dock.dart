import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';

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
    this.onNextTrack,
    this.onPreviousTrack,
    this.enableMusicSwipe = false,
    this.canChangeTracks = false,
    this.leftSwipeAction = 'forward',
    this.rightSwipeAction = 'backward',
    this.onMusicLongPress,
    this.currentTrackTitle,
    this.preview = false,
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
  final VoidCallback? onNextTrack;
  final VoidCallback? onPreviousTrack;
  final bool enableMusicSwipe;
  final bool canChangeTracks;
  final String leftSwipeAction;
  final String rightSwipeAction;
  final VoidCallback? onMusicLongPress;
  final String? currentTrackTitle;
  final bool preview;

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
          child: SolidPill(
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
          _MusicDockButton(
            isPlaying: isPlaying,
            hasMedia: hasMedia,
            isVideo: isVideo,
            canChangeTracks: enableMusicSwipe && canChangeTracks && !isVideo,
            leftSwipeAction: leftSwipeAction,
            rightSwipeAction: rightSwipeAction,
            onLongPress: onMusicLongPress,
            currentTrackTitle: currentTrackTitle,
            onTap: onBrowsePressed,
            onNext: onNextTrack,
            onPrevious: onPreviousTrack,
            activeColor: colors.primary,
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

class _MusicDockButton extends StatefulWidget {
  const _MusicDockButton({
    required this.isPlaying,
    required this.hasMedia,
    required this.isVideo,
    required this.canChangeTracks,
    required this.leftSwipeAction,
    required this.rightSwipeAction,
    required this.onTap,
    this.onLongPress,
    this.currentTrackTitle,
    required this.activeColor,
    this.onNext,
    this.onPrevious,
  });

  final bool isPlaying;
  final bool hasMedia;
  final bool isVideo;
  final bool canChangeTracks;
  final String leftSwipeAction;
  final String rightSwipeAction;
  final VoidCallback? onLongPress;
  final String? currentTrackTitle;
  final VoidCallback onTap;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final Color activeColor;

  @override
  State<_MusicDockButton> createState() => _MusicDockButtonState();
}

class _MusicDockButtonState extends State<_MusicDockButton>
    with SingleTickerProviderStateMixin {
  double _dragDistance = 0;
  Timer? _trackPopupTimer;
  String? _visibleTrackTitle;
  late final AnimationController _swipeHintController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.canChangeTracks) _playSwipeHint();
  }

  void _showTrackPopup(String? title) {
    if (title == null || title.trim().isEmpty || title == _visibleTrackTitle) return;
    _trackPopupTimer?.cancel();
    setState(() => _visibleTrackTitle = title.trim());
    _trackPopupTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _visibleTrackTitle = null);
    });
  }

  @override
  void didUpdateWidget(covariant _MusicDockButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTrackTitle != oldWidget.currentTrackTitle) {
      _showTrackPopup(widget.currentTrackTitle);
    }
    if (!oldWidget.canChangeTracks && widget.canChangeTracks) {
      _playSwipeHint();
    } else if (!widget.canChangeTracks) {
      _swipeHintController.stop();
      _swipeHintController.value = 0;
      _dragDistance = 0;
    }
  }

  void _playSwipeHint() {
    _swipeHintController
      ..stop()
      ..repeat(count: 3);
  }

  @override
  void dispose() {
    _trackPopupTimer?.cancel();
    _swipeHintController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDistance = (_dragDistance + details.delta.dx).clamp(-64.0, 64.0).toDouble();
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDistance;
    final didSwipe = distance.abs() >= 48 || velocity.abs() >= 450;
    if (didSwipe) {
      // Left defaults to forward/next; right defaults to backward/previous.
      // Users can independently reverse either direction in Navigation settings.
      final direction = distance.abs() >= 48 ? distance : velocity;
      final action = direction < 0
          ? widget.leftSwipeAction
          : widget.rightSwipeAction;
      if (action == 'forward') {
        widget.onNext?.call();
      } else {
        widget.onPrevious?.call();
      }
    }
    setState(() => _dragDistance = 0);
  }

  @override
  Widget build(BuildContext context) {
    final semanticsActions = widget.canChangeTracks
        ? <CustomSemanticsAction, VoidCallback>{
            CustomSemanticsAction(label: 'Next track'): () => widget.onNext?.call(),
            CustomSemanticsAction(label: 'Previous track'): () => widget.onPrevious?.call(),
          }
        : null;

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Semantics(
        button: true,
        label: widget.hasMedia && widget.isVideo ? 'Video player' : 'Music',
        customSemanticsActions: {
          ...?semanticsActions,
          CustomSemanticsAction(label: 'Open shortcuts'): () => widget.onLongPress?.call(),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate:
              widget.canChangeTracks ? _onDragUpdate : null,
          onHorizontalDragEnd:
              widget.canChangeTracks ? _onDragEnd : null,
          onHorizontalDragCancel: () {
            if (_dragDistance != 0) setState(() => _dragDistance = 0);
          },
          child: AnimatedScale(
            scale: _dragDistance == 0 ? 1 : 0.96,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: SolidPill(
              radius: BorderRadius.circular(32),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  child: AnimatedBuilder(
                    animation: _swipeHintController,
                    builder: (context, _) {
                      final hintPhase = _swipeHintController.value * math.pi * 2;
                      final hintOpacity = _dragDistance != 0
                          ? 1.0
                          : (math.sin(hintPhase).abs() * 0.9).clamp(0.0, 0.9);
                      final iconShift = _dragDistance != 0
                          ? (_dragDistance * 0.18).clamp(-8.0, 8.0)
                          : math.sin(hintPhase) * 3.0;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Transform.translate(
                              offset: Offset(iconShift, 0),
                              child: widget.isPlaying
                                  ? const _AnimatedEqualizer()
                                  : Icon(
                                      widget.hasMedia && widget.isVideo
                                          ? Icons.play_circle_fill_rounded
                                          : Icons.music_note_rounded,
                                      color: widget.activeColor,
                                      size: 25,
                                    ),
                            ),
                          ),
                          if (widget.canChangeTracks) ...[
                            Positioned(
                              left: 3,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Opacity(
                                  opacity: hintOpacity,
                                  child: Transform.translate(
                                    offset: Offset(-2 - hintOpacity * 2, 0),
                                    child: Icon(
                                      Icons.chevron_left_rounded,
                                      color: widget.activeColor,
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 3,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Opacity(
                                  opacity: hintOpacity,
                                  child: Transform.translate(
                                    offset: Offset(2 + hintOpacity * 2, 0),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      color: widget.activeColor,
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          ),
          ),
          if (_visibleTrackTitle != null)
            Positioned(
              bottom: 70,
              left: -76,
              width: 216,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  reverseDuration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.22),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  ),
                  child: _TrackChangePopup(
                    key: ValueKey(_visibleTrackTitle),
                    title: _visibleTrackTitle!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackChangePopup extends StatelessWidget {
  const _TrackChangePopup({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 5))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
          ],
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
