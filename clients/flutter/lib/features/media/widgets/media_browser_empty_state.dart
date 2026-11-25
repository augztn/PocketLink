import 'package:material_ui/material_ui.dart';

class MediaBrowserEmptyState extends StatelessWidget {
  const MediaBrowserEmptyState({
    required this.icon,
    required this.message,
    required this.onScan,
    required this.showScanAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final VoidCallback onScan;
  final bool showScanAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 52,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (showScanAction)
                OutlinedButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan again'),
                ),
            ],
          ),
        ),
      );
}
