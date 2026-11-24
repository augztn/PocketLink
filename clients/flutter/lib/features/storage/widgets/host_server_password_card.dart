import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';

class HostServerPasswordCard extends StatelessWidget {
  const HostServerPasswordCard({
    required this.controller,
    required this.configured,
    required this.busy,
    required this.obscurePassword,
    required this.onToggleVisibility,
    required this.onSave,
    super.key,
  });

  final TextEditingController controller;
  final bool configured;
  final bool busy;
  final bool obscurePassword;
  final VoidCallback onToggleVisibility;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Native server password',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (configured)
                const PocketLinkStatusPill(label: 'Configured', granted: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            configured
                ? 'A salted password verifier is saved on this device.'
                : 'Choose a password with at least 12 characters.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            obscureText: obscurePassword,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
            enabled: !busy,
            decoration: InputDecoration(
              labelText: 'New server password',
              helperText: 'Never uploaded or stored in plaintext.',
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: IconButton(
                tooltip: obscurePassword ? 'Show password' : 'Hide password',
                onPressed: busy ? null : onToggleVisibility,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onSave,
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: Text(configured ? 'Update password' : 'Save password'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
