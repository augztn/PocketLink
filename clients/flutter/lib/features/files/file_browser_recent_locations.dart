import 'package:material_ui/material_ui.dart';

import '../../core/storage/home_activity_store.dart';

Future<void> showFileBrowserRecentLocations({
  required BuildContext context,
  required List<HomeActivityItem> recent,
  required ValueChanged<HomeActivityItem> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: recent.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('No recent files or folders yet')),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: recent.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, index) {
                  final item = recent[index];
                  return ListTile(
                    leading: Icon(
                      item.isFolder
                          ? Icons.folder_rounded
                          : Icons.history_rounded,
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.path.isEmpty ? 'Storage root' : item.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onSelected(item);
                    },
                  );
                },
              ),
      ),
    ),
  );
}
