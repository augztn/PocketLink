import 'package:flutter/material.dart';

/// Lightweight shimmer host inspired by Mochy's loading placeholders.
/// Respects the operating-system and PocketLink reduced-motion setting.
class PocketLinkShimmer extends StatefulWidget {
  const PocketLinkShimmer({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<PocketLinkShimmer> createState() => _PocketLinkShimmerState();
}

class _PocketLinkShimmerState extends State<PocketLinkShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void didUpdateWidget(covariant PocketLinkShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled && !MediaQuery.of(context).disableAnimations) {
      _controller.repeat();
    } else if (!widget.enabled || MediaQuery.of(context).disableAnimations) {
      _controller.stop();
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
    if (!widget.enabled || reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final shift = -1.4 + _controller.value * 2.8;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(shift - 0.7, 0),
            end: Alignment(shift + 0.7, 0),
            colors: const [
              Color(0x40FFFFFF),
              Color(0xA6FFFFFF),
              Color(0x40FFFFFF),
            ],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Variable-width text placeholder, matching Mochy's TextPlaceholder.
class PocketLinkSkeletonLine extends StatelessWidget {
  const PocketLinkSkeletonLine({
    this.widthFactor = 0.58,
    this.height = 14,
    this.radius = 6,
    super.key,
  });

  final double widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor.clamp(0.08, 1.0).toDouble(),
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(radius)),
          ),
        ),
      ),
    );
  }
}

/// List-row placeholder: thumbnail plus two text lines.
class PocketLinkSkeletonListTile extends StatelessWidget {
  const PocketLinkSkeletonListTile({this.thumbnailSize = 48, super.key});

  final double thumbnailSize;

  @override
  Widget build(BuildContext context) => PocketLinkShimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Container(
                width: thumbnailSize,
                height: thumbnailSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PocketLinkSkeletonLine(widthFactor: 0.72),
                    SizedBox(height: 8),
                    PocketLinkSkeletonLine(widthFactor: 0.42, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Grid-card placeholder: square artwork and two text lines.
class PocketLinkSkeletonGridTile extends StatelessWidget {
  const PocketLinkSkeletonGridTile({super.key});

  @override
  Widget build(BuildContext context) => PocketLinkShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const PocketLinkSkeletonLine(widthFactor: 0.82),
            const SizedBox(height: 6),
            const PocketLinkSkeletonLine(widthFactor: 0.56, height: 10),
          ],
        ),
      );
}

/// Button placeholder, matching Mochy's pill-shaped loading button.
class PocketLinkSkeletonButton extends StatelessWidget {
  const PocketLinkSkeletonButton({this.width = 120, this.height = 44, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => PocketLinkShimmer(
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
}
