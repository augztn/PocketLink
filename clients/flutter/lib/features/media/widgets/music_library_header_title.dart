import 'package:material_ui/material_ui.dart';

class MusicLibraryHeaderTitle extends StatelessWidget {
  const MusicLibraryHeaderTitle({
    required this.subtitle,
    required this.menuOpen,
    required this.titleColor,
    super.key,
  });

  final String subtitle;
  final bool menuOpen;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 2, right: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  'Music',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: menuOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: titleColor,
                    size: 20,
                  ),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.62),
                  fontSize: 11,
                  height: 1.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
