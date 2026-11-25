import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

/// Presents an image preview without taking ownership of file loading/history.
Future<void> showFileBrowserImagePreview({
  required BuildContext context,
  required String name,
  required Uint8List bytes,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This image format could not be previewed.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
