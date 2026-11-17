import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/widgets/home_server_app_bar.dart';
import 'package:flutter/services.dart';

class LocalStorageSetupScreen extends StatefulWidget {
  const LocalStorageSetupScreen({super.key});

  @override
  State<LocalStorageSetupScreen> createState() => _LocalStorageSetupScreenState();
}

class _LocalStorageSetupScreenState extends State<LocalStorageSetupScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('homeserver/saf');
  Map<String, dynamic> _status = const {};
  String? _token;
  final _serverPasswordController = TextEditingController();
  bool _serverPasswordConfigured = false;
  String? _error;
  bool _busy = false;
  bool _refreshingStorage = false;
  bool _scanningMedia = false;
  bool _watchingMediaScan = false;
  Map<String, dynamic> _mediaScanStatus = const {};
  List<Map<String, dynamic>> _discoveredVolumes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeEvent);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'storageChanged') {
      await _refresh();
    } else if (call.method == 'storageError') {
      setState(() {
        _busy = false;
        _error = call.arguments?.toString() ?? 'Could not save storage permission.';
      });
    } else if (call.method == 'selectionCancelled') {
      setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      final token = await _channel.invokeMethod<String>('token');
      final scanStatusRaw = await _channel.invokeMethod<String>('mediaIndexStatus');
      final scanStatus = scanStatusRaw == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(scanStatusRaw) as Map);
      if (!mounted) return;
      setState(() {
        _status = status ?? const {};
        _discoveredVolumes = (status?['discoveredVolumes'] as List<dynamic>? ?? const [])
            .whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        _token = token;
        _mediaScanStatus = scanStatus;
        _scanningMedia = scanStatus['state'] == 'scanning';
        _serverPasswordConfigured = status?['serverPasswordConfigured'] == true;
        _error = status?['error']?.toString();
        _busy = false;
      });
      if (_scanningMedia) unawaited(_watchMediaScan());
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Native Android storage support is unavailable in this build.');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not read storage status.');
    }
  }

  Future<void> _refreshStorage() async {
    if (_refreshingStorage || _busy) return;
    setState(() {
      _refreshingStorage = true;
      _error = null;
    });
    try {
      await _refresh();
    } finally {
      if (mounted) setState(() => _refreshingStorage = false);
    }
  }

  Future<void> _watchMediaScan() async {
    if (_watchingMediaScan) return;
    _watchingMediaScan = true;
    try {
      while (mounted && _scanningMedia) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final raw = await _channel.invokeMethod<String>('mediaIndexStatus');
        if (raw == null) continue;
        final status = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (!mounted) return;
        setState(() {
          _mediaScanStatus = status;
          _scanningMedia = status['state'] == 'scanning';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _scanningMedia = false;
          _error = error.message ?? 'Could not read media scan progress.';
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _scanningMedia = false;
          _error = 'The media scan returned an invalid status.';
        });
      }
    } finally {
      _watchingMediaScan = false;
    }
  }

  Future<void> _scanMediaAndFiles() async {
    if (_scanningMedia || _busy) return;
    setState(() {
      _scanningMedia = true;
      _error = null;
    });
    try {
      final initial = await _channel.invokeMethod<String>('refreshMediaIndex');
      if (initial != null && mounted) {
        setState(() => _mediaScanStatus =
            Map<String, dynamic>.from(jsonDecode(initial) as Map));
      }
      // Poll only while this user-requested scan is active; no permanent timer.
      for (var attempt = 0; attempt < 240; attempt++) {
        if (!mounted) return;
        await Future<void>.delayed(const Duration(seconds: 1));
        final raw = await _channel.invokeMethod<String>('mediaIndexStatus');
        if (raw == null) continue;
        final status = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (!mounted) return;
        setState(() => _mediaScanStatus = status);
        if (status['state'] != 'scanning') break;
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error =
          error.message ?? 'Could not start the media and file scan.');
    } on FormatException {
      if (mounted) setState(() => _error = 'The media scan returned an invalid status.');
    } finally {
      if (mounted) {
        setState(() => _scanningMedia = _mediaScanStatus['state'] == 'scanning');
      }
    }
  }

  Future<void> _saveServerPassword() async {
    final password = _serverPasswordController.text;
    if (password.length < 12) {
      setState(() => _error = 'Use at least 12 characters for the server password.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<bool>(
        'setServerPassword',
        {'password': password},
      );
      _serverPasswordController.clear();
      await _refresh();
      if (mounted) {
        setState(() => _error = 'Native server password saved. It is stored as a salted verifier.');
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not save server password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestBackgroundAccess() async {
    setState(() { _busy = true; _error = null; });
    try {
      final alreadyAllowed = await _channel.invokeMethod<bool>('requestBackgroundAccess');
      await _refresh();
      if (mounted && alreadyAllowed != true) {
        setState(() => _error =
            'If Android shows a battery restriction prompt, choose Allow. Then return here and refresh status.');
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() {
        _busy = false;
        _error = error.message ?? 'Could not open background activity settings.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBackgroundSettings() async {
    try {
      await _channel.invokeMethod<bool>('openBackgroundAccessSettings');
    } on PlatformException catch (error) {
      if (mounted) setState(() =>
          _error = error.message ?? 'Could not open Android battery settings.');
    }
  }

  Future<void> _requestInternalStorageAccess() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<bool>('requestInternalStorageAccess');
      // Android opens its special-access settings page. Refresh after the user
      // returns; never assume the permission was granted just because settings opened.
      if (mounted) {
        setState(() {
          _error = 'Enable “Allow access to manage all files” for HomeServer, return here, then refresh status.';
          _busy = false;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() {
        _busy = false;
        _error = error.message ?? 'Could not open Android storage permission settings.';
      });
    }
  }

  Future<void> _select(String volumeId) async {
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<void>('selectVolume', {'volumeId': volumeId});
    } on PlatformException catch (error) {
      if (mounted) setState(() { _busy = false; _error = error.message ?? 'Could not open Android storage picker.'; });
    }
  }

  Future<void> _start() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<bool>('start');
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final status = await _channel.invokeMapMethod<String, dynamic>('status');
        if (!mounted) return;
        if (status?['running'] == true || status?['error'] != null) {
          setState(() {
            _status = status ?? const {};
            _error = status?['error']?.toString();
          });
          return;
        }
      }
      if (mounted) {
        final status = await _channel.invokeMapMethod<String, dynamic>('status');
        setState(() {
          _status = status ?? const {};
          _error = 'Android storage service did not become ready. Check the app notification and try again.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not start local storage access.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _channel.invokeMethod<bool>('stop');
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not stop local storage access.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverPasswordController.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final legacySelected = (_status['usb1'] != null && _status['usb1'] != 'Not selected') ||
        (_status['usb2'] != null && _status['usb2'] != 'Not selected');
    final running = _status['running'] == true;
    final internalGranted = _status['internalStorageGranted'] == true;
    final backgroundGranted = _status['backgroundAccessGranted'] == true;
    final selectedVolumeCount = _discoveredVolumes.where((v) => v['selected'] == true).length;
    final canStart = internalGranted || legacySelected || selectedVolumeCount > 0;

    return Scaffold(
      appBar: const HomeServerAppBar(title: Text('Host PocketLink')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.phonelink_setup_rounded, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Host PocketLink here', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(
                        'Prepare this phone for reliable file access and background server operation.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SetupSectionTitle(title: 'Device permissions', subtitle: 'Allow the access PocketLink needs to host your files.'),
          const SizedBox(height: 10),
          _SetupStatusTile(
            icon: Icons.folder_rounded,
            title: 'Internal shared storage',
            subtitle: internalGranted
                ? 'All-files access is enabled.'
                : 'Needed for Music, Movies, Pictures, DCIM and Download.',
            status: internalGranted ? 'Enabled' : 'Action needed',
            granted: internalGranted,
            onTap: _busy || internalGranted ? null : _requestInternalStorageAccess,
          ),
          const SizedBox(height: 10),
          _SetupStatusTile(
            icon: Icons.battery_charging_full_rounded,
            title: 'Background connection',
            subtitle: backgroundGranted
                ? 'Battery optimization is disabled for this app.'
                : 'Allow background activity to reduce the chance Android suspends the server.',
            status: backgroundGranted ? 'Protected' : 'Recommended',
            granted: backgroundGranted,
            onTap: _busy || backgroundGranted ? null : _requestBackgroundAccess,
          ),
          if (!backgroundGranted) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _openBackgroundSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open battery settings'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh device status'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 24),
          const _SetupSectionTitle(title: 'Server security', subtitle: 'Set the password used by remote clients to connect.'),
          const SizedBox(height: 10),
          Container(
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
                    Expanded(child: Text('Native server password', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    if (_serverPasswordConfigured)
                      const _StatusPill(label: 'Configured', granted: true),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _serverPasswordConfigured
                      ? 'A salted password verifier is saved on this device.'
                      : 'Choose a password with at least 12 characters.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _serverPasswordController,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'New server password',
                    helperText: 'Never uploaded or stored in plaintext.',
                    prefixIcon: const Icon(Icons.password_rounded),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _saveServerPassword,
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: Text(_serverPasswordConfigured ? 'Update password' : 'Save password'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: _SetupSectionTitle(
                  title: 'USB / External Storage',
                  subtitle: 'Connect a USB drive or external SSD. Detected drives appear here.',
                ),
              ),
              IconButton(
                tooltip: 'Refresh connected storage',
                onPressed: _busy || _refreshingStorage ? null : _refreshStorage,
                icon: _refreshingStorage
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_discoveredVolumes.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Icon(Icons.usb_rounded, size: 34, color: colors.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text('No removable drive detected', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Connect or reconnect your USB drive. You can also choose its folder manually.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _select(
                      'usb-manual-${DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0').substring(0, 16)}',
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Choose storage folder'),
                  ),
                ],
              ),
            ),
          ..._discoveredVolumes.map((volume) {
            final selected = volume['selected'] == true;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VolumeTile(
                title: volume['name']?.toString() ?? 'USB storage',
                value: selected ? 'Access granted · ready to use' : 'Detected · approve access to use',
                selected: selected,
                onTap: _busy || selected ? null : () => _select(volume['id'].toString()),
              ),
            );
          }),
          const SizedBox(height: 24),
          const _SetupSectionTitle(
            title: 'Device media & files',
            subtitle: 'Index photos, videos, music and searchable files in the background.',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _scanningMedia ? Icons.sync_rounded : Icons.perm_media_outlined,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        switch (_mediaScanStatus['state']) {
                          'scanning' => 'Scanning device storage',
                          'complete' => 'Media and files indexed',
                          'partial' => 'Scan completed with skipped items',
                          'failed' => 'Scan failed',
                          _ => 'Media scan ready',
                        },
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_mediaScanStatus['state'] == 'complete')
                      const _StatusPill(label: 'Complete', granted: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_mediaScanStatus['scanned'] ?? 0} items scanned · '
                  '${_mediaScanStatus['media_count'] ?? 0} media · '
                  '${_mediaScanStatus['file_count'] ?? 0} files',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                if (_scanningMedia) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
                if (_mediaScanStatus['last_error'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _mediaScanStatus['last_error'].toString(),
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _scanningMedia || _busy ? null : _scanMediaAndFiles,
                    icon: _scanningMedia
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_scanningMedia ? 'Scanning…' : 'Scan media & files now'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The scan runs on the host in the background. Existing indexed results remain available while it updates.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: colors.error, size: 19),
                  const SizedBox(width: 9),
                  Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: colors.onErrorContainer))),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(running ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: running ? Colors.green : colors.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Local storage service', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    _StatusPill(label: running ? 'Running' : 'Stopped', granted: running),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  running ? 'Your device storage bridge is active.' : 'Start the service when your storage permissions are ready.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || (!running && !canStart) ? null : (running ? _stop : _start),
                    icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                    label: Text(running ? 'Stop storage service' : 'Start storage service'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            leading: const Icon(Icons.key_outlined),
            title: const Text('Backend bridge token'),
            subtitle: const Text('Temporary compatibility setting'),
            children: [
              SelectableText(_token ?? 'Loading…'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _token == null ? null : () => Clipboard.setData(ClipboardData(text: _token!)),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy token'),
                ),
              ),
              Text(
                'This token is used by the current Termux backend. It will no longer be needed once the native PocketLink API is enabled.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupSectionTitle extends StatelessWidget {
  const _SetupSectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.granted});
  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = granted ? Colors.green : colors.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _SetupStatusTile extends StatelessWidget {
  const _SetupStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.granted,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final bool granted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (granted ? Colors.green : colors.primary).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: granted ? Colors.green : colors.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.35)),
                    const SizedBox(height: 8),
                    _StatusPill(label: status, granted: granted),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ] else if (granted) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded, color: Colors.green),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeTile extends StatelessWidget {
  const _VolumeTile({required this.title, required this.value, required this.selected, required this.onTap});
  final String title;
  final String value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.usb_rounded, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(value, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: Colors.green)
              else
                Icon(Icons.folder_open_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}