import 'package:material_ui/material_ui.dart';

Future<String?> showFileBrowserSortOptions({
  required BuildContext context,
  required String selectedSort,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    showDragHandle: true,
    builder: (sheetContext) {
      final sheetColors = Theme.of(sheetContext).colorScheme;
      const options = [
        ('name', 'Name', Icons.sort_by_alpha_rounded),
        ('newest', 'Newest', Icons.schedule_rounded),
        ('largest', 'Largest', Icons.storage_rounded),
      ];
      return SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: sheetColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort files',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final option in options) ...[
                if (option.$1 == 'newest')
                  const Padding(
                    padding: EdgeInsets.only(left: 56, right: 16),
                    child: Divider(height: 1, thickness: 1),
                  ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(option.$3),
                  title: Text(option.$2),
                  trailing: selectedSort == option.$1
                      ? const Icon(Icons.check_rounded, size: 18)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
