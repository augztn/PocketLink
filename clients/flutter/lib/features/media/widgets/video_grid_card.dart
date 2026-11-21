import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/liquid_glass_pill.dart';
import '../../../core/widgets/smoked_glass_popover_menu.dart';

class VideoGridCard extends StatelessWidget {
  const VideoGridCard({
    required this.title,
    required this.extension,
    required this.sizeLabel,
    required this.favorite,
    required this.artwork,
    required this.durationBadge,
    required this.metadataLabel,
    required this.onOpen,
    required this.onDownload,
    required this.onToggleFavorite,
    super.key,
  });

  final String title;
  final String extension;
  final String sizeLabel;
  final bool favorite;
  final Widget artwork;
  final Widget durationBadge;
  final Widget metadataLabel;
  final VoidCallback onOpen;
  final Future<void> Function() onDownload;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.48),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    artwork,
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          extension,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(right: 8, bottom: 8, child: durationBadge),
                    Center(
                      child: ClipOval(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: SmokedGlassPopoverMenu<String>(
                        tooltip: 'Video actions',
                        items: const [
                          SmokedGlassPopoverMenuItem(
                            value: 'download',
                            label: 'Download',
                            icon: Icons.download_rounded,
                          ),
                        ],
                        onSelected: (action) async {
                          if (action == 'download') await onDownload();
                        },
                        child: const GlassCircleButton(
                          tooltip: 'Open video actions',
                          onPressed: null,
                          size: 28,
                          child: Icon(Icons.more_vert_rounded, size: 15),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: favorite
                            ? 'Remove favourite'
                            : 'Add favourite',
                        onPressed: onToggleFavorite,
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite
                              ? const Color(0xFFFF6B8A)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(child: metadataLabel),
                        Text(
                          sizeLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
