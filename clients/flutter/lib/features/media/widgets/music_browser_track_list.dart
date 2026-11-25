import 'package:material_ui/material_ui.dart';

class MusicBrowserTrackList extends StatelessWidget {
  const MusicBrowserTrackList({
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.topPadding,
    required this.bottomPadding,
    super.key,
  });

  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: controller,
        padding: EdgeInsets.fromLTRB(0, topPadding, 0, bottomPadding),
        itemCount: itemCount,
        separatorBuilder: (_, __) => Container(
          height: 1,
          margin: const EdgeInsets.only(left: 76),
          color: Colors.white.withValues(alpha: 0.06),
        ),
        itemBuilder: itemBuilder,
      );
}
