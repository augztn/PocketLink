import 'package:material_ui/material_ui.dart';

/// Presents folder breadcrumbs and the media entries at the current level.
class MediaFolderContent extends StatelessWidget {
  const MediaFolderContent({
    required this.breadcrumbs,
    required this.controller,
    required this.padding,
    required this.children,
    this.physics,
    super.key,
  });

  final Widget breadcrumbs;
  final ScrollController controller;
  final EdgeInsetsGeometry padding;
  final List<Widget> children;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          breadcrumbs,
          Expanded(
            child: ListView(
              controller: controller,
              physics: physics,
              padding: padding,
              children: children.isEmpty
                  ? const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No media in this folder')),
                      ),
                    ]
                  : children,
            ),
          ),
        ],
      );
}
