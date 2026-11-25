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
