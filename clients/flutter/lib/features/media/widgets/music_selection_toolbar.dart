import 'package:material_ui/material_ui.dart';

class MusicSelectionToolbar extends StatelessWidget {
  const MusicSelectionToolbar({
    required this.selectedCount,
    required this.foreground,
    required this.onDone,
    super.key,
  });

  final int selectedCount;
  final Color foreground;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: LiquidGlassSurface(
          radius: BorderRadius.circular(22),
          refractive: true,
          lightRefractive: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '$selectedCount selected',
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Done selecting',
                onPressed: onDone,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      );
}
