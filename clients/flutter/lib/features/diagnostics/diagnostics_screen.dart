import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../settings/widgets/settings_components.dart';

import '../../core/logging/app_logger.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  int _size = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final size = await AppLogger.logSize();
      if (mounted) setState(() {
        _size = size;
        _error = null;
      });
    } catch (error, stack) {
      await AppLogger.error('Could not read diagnostic log size', error: error, stackTrace: stack);
      if (mounted) setState(() => _error = 'Could not read diagnostic logs.');
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppLogger.info('Diagnostic log export requested');
      final file = await AppLogger.createDiagnosticFile();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'PocketLink diagnostic logs',
        text: 'PocketLink diagnostic logs. Review before sharing; logs are designed to exclude passwords and authentication headers.',
      );
    } catch (error, stack) {
      await AppLogger.error('Diagnostic log export failed', error: error, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export diagnostic logs.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear diagnostic logs?'),
        content: const Text('This permanently deletes the saved troubleshooting history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.clear();
    await AppLogger.info('Diagnostic log cleared');
    await _refresh();
  }

  String get _sizeLabel => _size < 1024
      ? '$_size B'
      : _size < 1024 * 1024
          ? '${(_size / 1024).toStringAsFixed(1)} KB'
          : '${(_size / (1024 * 1024)).toStringAsFixed(2)} MB';

  @override
  Widget build(BuildContext context) {
    final topPadding = LayoutInsetsScope.of(context).topClearance + 6;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PocketLinkAppBar(title: Text('Diagnostics', style: TextStyle(fontSize: 20))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          topPadding,
          16,
          settingsListBottomPadding(context),
        ),
        children: [
          const SettingsSectionHeader('Diagnostics'),
          SettingsGroupCard(children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.monitor_heart_outlined),
                      SizedBox(width: 10),
                      Text('Diagnostic log'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('$_sizeLabel saved on this device'),
                  const SizedBox(height: 8),
                  const Text(
                    'PocketLink records connection attempts, API request IDs, response times, retries, navigation events, app foreground/background transitions, memory snapshots, errors and crash details. Logs are stored privately on this device and rotate automatically to limit storage use.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_busy ? 'Preparing logs…' : 'Generate & share log file'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh log size'),
                  ),
                  TextButton.icon(
                    onPressed: _size == 0 ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear logs'),
                  ),
                ],
              ),
            ),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacy'),
            subtitle: Text('Passwords, usernames, authentication headers, tokens, server addresses and IP addresses are redacted from exported logs. Device OS details, error messages and file-system details may still be present. Review the file before sending it.'),
            isThreeLine: true,
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('What to include in a bug report'),
            subtitle: Text('Share the exported log together with the time the issue occurred, the screen you were using and the action that triggered it. Never send your server password or private keys.'),
            isThreeLine: true,
          ),
          ]),
        ],
      ),
    );
  }
}

/// Inline guidance shown in the Client and Host sections so users can
/// understand diagnostic collection and privacy before opening the log tools.
class DiagnosticsGuidanceCard extends StatelessWidget {
  const DiagnosticsGuidanceCard({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Diagnostics & logs',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Diagnostic log',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'PocketLink records connection attempts, API request IDs, response times, retries, navigation events, app foreground/background transitions, memory snapshots, errors and crash details. Logs stay on this device and rotate automatically.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Privacy',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Exported logs redact passwords, usernames, authentication headers, tokens, server addresses and IP addresses. Device OS details, error messages and file-system details may still appear. Review the file before sharing it.',
            ),
            const SizedBox(height: 12),
            const Text(
              'What to include in a bug report',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Share the exported log, the approximate time of the issue, the screen you were using and the action that triggered it. Never send your server password or private keys.',
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.article_outlined),
                label: const Text('Open diagnostics & log tools'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
