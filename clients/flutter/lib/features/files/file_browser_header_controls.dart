import 'package:material_ui/material_ui.dart';

import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';

/// Displays the current storage path without owning navigation state.
class FileBrowserBreadcrumbs extends StatelessWidget {
  const FileBrowserBreadcrumbs({
    required this.path,
    required this.storageLabel,
    required this.onNavigate,
    super.key,
  });

  final String path;
  final String storageLabel;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();

    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: SizedBox(
        height: 30,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => onNavigate(''),
              child: Text(
                storageLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (var i = 0; i < segments.length; i++) ...[
              const Center(child: Icon(Icons.chevron_right_rounded, size: 15)),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: i == segments.length - 1
                    ? null
                    : () => onNavigate(segments.take(i + 1).join('/')),
                child: Text(segments[i], style: theme.textTheme.labelSmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Presents file-type filters and counts; selection remains owned by the screen.
class FileCategoryFilter extends StatelessWidget {
  const FileCategoryFilter({
    required this.selectedCategory,
    required this.counts,
    required this.onSelected,
    super.key,
  });

  final String selectedCategory;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SmokedGlassPopoverMenu<String>(
          tooltip: 'Filter file types',
          itemHeight: 44,
          menuVerticalPadding: 6,
          itemHorizontalPadding: 14,
          trailingWidth: 52,
          items: [
            for (final category in const [
              'All', 'Images', 'Videos', 'Music', 'Documents',
            ])
              SmokedGlassPopoverMenuItem(
                value: category,
                label: category,
                icon: switch (category) {
                  'Images' => Icons.image_outlined,
                  'Videos' => Icons.movie_outlined,
                  'Music' => Icons.music_note_outlined,
                  'Documents' => Icons.description_outlined,
                  _ => Icons.apps_rounded,
                },
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    '${counts[category] ?? 0}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFA1A7B3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 20,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: selectedCategory == category
                          ? const Icon(Icons.check_rounded, size: 16)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ]),
              ),
          ],
          onSelected: onSelected,
          child: SmokedGlassSurface(
            radius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.filter_list_rounded, size: 17),
                const SizedBox(width: 7),
                Text(
                  'Filter: $selectedCategory',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
