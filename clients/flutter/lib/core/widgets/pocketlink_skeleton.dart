import 'package:material_ui/material_ui.dart';

/// Shared PocketLink skeleton layouts with the same restrained shimmer used
/// by Discover. Callers choose geometry that matches the screen being loaded.
class PocketLinkSkeleton extends StatefulWidget {
  const PocketLinkSkeleton({required this.child, super.key});

  final Widget child;

  static Widget musicList({int rows = 6}) => PocketLinkSkeleton(
    child: Column(
      children: List.generate(rows, (index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          const PocketLinkSkeletonBlock(width: 48, height: 48, radius: 12),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PocketLinkSkeletonBlock(width: index.isEven ? 154 : 122, height: 12, radius: 6),
              const SizedBox(height: 8),
              PocketLinkSkeletonBlock(width: index.isEven ? 92 : 112, height: 9, radius: 5),
            ],
          )),
          const PocketLinkSkeletonBlock(width: 18, height: 18, radius: 9),
        ]),
      )),
    ),
  );

  static Widget photoGrid({
    int crossAxisCount = 3,
    int count = 18,
    double spacing = 2,
    double childAspectRatio = 1,
    EdgeInsets padding = EdgeInsets.zero,
  }) => PocketLinkSkeleton(
    child: GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const PocketLinkSkeletonBlock(
        radius: 2,
        expand: true,
      ),
    ),
  );

  static Widget videoGrid({
    EdgeInsets padding = EdgeInsets.zero,
    int count = 8,
  }) => PocketLinkSkeleton(
    child: GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: .82,
      ),
      itemCount: count,
      itemBuilder: (_, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: 16 / 9,
            child: PocketLinkSkeletonBlock(radius: 12, expand: true),
          ),
          const SizedBox(height: 10),
          PocketLinkSkeletonBlock(width: index.isEven ? 148 : 116, height: 11, radius: 5),
          const SizedBox(height: 7),
          const PocketLinkSkeletonBlock(width: 86, height: 9, radius: 5),
        ],
      ),
    ),
  );

  static Widget videoList({
    EdgeInsets padding = EdgeInsets.zero,
    int rows = 7,
  }) => PocketLinkSkeleton(
    child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          const PocketLinkSkeletonBlock(width: 104, height: 64, radius: 10),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PocketLinkSkeletonBlock(width: index.isEven ? 156 : 122, height: 11, radius: 5),
              const SizedBox(height: 8),
              const PocketLinkSkeletonBlock(width: 94, height: 9, radius: 5),
              const SizedBox(height: 7),
              const PocketLinkSkeletonBlock(width: 66, height: 8, radius: 4),
            ],
          )),
        ]),
      ),
    ),
  );

  static Widget fileList({
    EdgeInsets padding = EdgeInsets.zero,
    int rows = 8,
  }) => PocketLinkSkeleton(
    child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Row(children: [
          const PocketLinkSkeletonBlock(width: 48, height: 48, radius: 14),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PocketLinkSkeletonBlock(width: index.isEven ? 164 : 126, height: 11, radius: 5),
              const SizedBox(height: 8),
              const PocketLinkSkeletonBlock(width: 76, height: 9, radius: 5),
            ],
          )),
          const PocketLinkSkeletonBlock(width: 20, height: 20, radius: 10),
        ]),
      ),
    ),
  );

  static Widget fileGrid({
    EdgeInsets padding = EdgeInsets.zero,
    int count = 8,
  }) => PocketLinkSkeleton(
    child: GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 156,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: count,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PocketLinkSkeletonBlock(width: 44, height: 44, radius: 14),
            const Spacer(),
            PocketLinkSkeletonBlock(width: index.isEven ? 112 : 82, height: 11, radius: 5),
            const SizedBox(height: 8),
            const PocketLinkSkeletonBlock(width: 58, height: 9, radius: 5),
          ],
        ),
      ),
    ),
  );

  @override
  State<PocketLinkSkeleton> createState() => _PocketLinkSkeletonState();
}

class _PocketLinkSkeletonState extends State<PocketLinkSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _visible = true;
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final shift = _reduceMotion ? 0.0 : _controller.value * 2.8;
      return AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
        child: ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-1.4 + shift, 0),
          end: Alignment(-.4 + shift, 0),
          colors: const [
            Color(0xFF1A1A1E),
            Color(0xFF2A2A30),
            Color(0xFF1A1A1E),
          ],
          stops: const [0.1, 0.5, 0.9],
        ).createShader(bounds),
        child: child,
        ),
      );
    },
  );
}

class PocketLinkSkeletonBlock extends StatelessWidget {
  const PocketLinkSkeletonBlock({
    this.width,
    required this.height,
    this.radius = 8,
    this.expand = false,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final block = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (expand) return SizedBox.expand(child: block);
    return SizedBox(width: width, height: height, child: block);
  }
}
