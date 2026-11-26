import 'package:material_ui/material_ui.dart';

Future<String?> showFileBrowserNameDialog({
  required BuildContext context,
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  } finally {
    controller.dispose();
  }
}

Future<bool> confirmFileBrowserDelete({
  required BuildContext context,
  required String itemName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete item?'),
      content: Text('Delete "$itemName"? Folders must be empty.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<void> showFileBrowserDetails({
  required BuildContext context,
  required String name,
  required String path,
  required String storage,
  required String size,
  required String modified,
  required bool isDirectory,
}) async {
  final parsedModified = DateTime.tryParse(modified)?.toLocal();
  final modifiedLabel = parsedModified == null
      ? (modified.isEmpty ? 'Unavailable' : modified)
      : MaterialLocalizations.of(context).formatFullDate(parsedModified);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FileDetailRow(label: 'Type', value: isDirectory ? 'Folder' : 'File'),
          _FileDetailRow(label: 'Size', value: isDirectory ? '—' : size),
          _FileDetailRow(label: 'Modified', value: modifiedLabel),
          _FileDetailRow(label: 'Storage', value: storage),
          const SizedBox(height: 10),
          const Text('Location', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SelectableText(path, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _FileDetailRow extends StatelessWidget {
  const _FileDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 82, child: Text(label, style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ))),
      Expanded(child: Text(value)),
    ]),
  );
}
