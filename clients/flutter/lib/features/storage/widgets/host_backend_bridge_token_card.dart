import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';

class HostBackendBridgeTokenCard extends StatelessWidget {
  const HostBackendBridgeTokenCard({
    required this.token,
    required this.statusLoaded,
    required this.obscureToken,
    required this.onToggleVisibility,
    required this.onCopy,
    super.key,
  });

  final String? token;
  final bool statusLoaded;
  final bool obscureToken;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Backend bridge token',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              PocketLinkStatusPill(
                label: token != null ? 'Ready' : statusLoaded ? 'Unavailable' : 'Loading',
                granted: token != null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Used by the Termux backend to authenticate with this phone’s Android USB storage bridge. It is separate from the native server password.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (token == null)
            Text(
              statusLoaded
                  ? 'The bridge token could not be loaded. Refresh the device status and try again.'
                  : 'Loading bridge token…',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      obscureToken ? '••••••••••••••••••••••••' : token!,
                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    tooltip: obscureToken ? 'Show bridge token' : 'Hide bridge token',
                    onPressed: onToggleVisibility,
                    icon: Icon(
                      obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy bridge token',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
