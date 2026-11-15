import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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
      final file = await AppLogger.createDiagnosticFile();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'HomeServer diagnostic logs',
        text: 'HomeServer diagnostic logs. Review before sharing; logs are designed to exclude passwords and authentication headers.',
      );
      await AppLogger.info('Diagnostic log export requested');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics & logs')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
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
                    'HomeServer records connection attempts, API status codes, app errors and crash details. Logs are stored privately on this device and rotate automatically to limit storage use.',
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
          ),
          const SizedBox(height: 12),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacy'),
            subtitle: Text('Passwords, Basic authentication headers and common token fields are redacted. Logs may still contain device errors, server addresses and file-system error details. Review the file before sending it.'),
            isThreeLine: true,
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('What to include in a bug report'),
            subtitle: Text('Share the exported log together with the time the issue occurred, the screen you were using and the action that triggered it. Never send your server password or private keys.'),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}
