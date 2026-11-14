import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocalStorageSetupScreen extends StatefulWidget {
  const LocalStorageSetupScreen({super.key});

  @override
  State<LocalStorageSetupScreen> createState() => _LocalStorageSetupScreenState();
}

class _LocalStorageSetupScreenState extends State<LocalStorageSetupScreen> {
  static const _channel = MethodChannel('homeserver/saf');
  Map<String, dynamic> _status = const {};
  String? _token;
  final _serverPasswordController = TextEditingController();
  bool _serverPasswordConfigured = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onNativeEvent);
    _refresh();
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
      if (!mounted) return;
      setState(() {
        _status = status ?? const {};
        _token = token;
        _serverPasswordConfigured = status?['serverPasswordConfigured'] == true;
        _error = status?['error']?.toString();
        _busy = false;
      });
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Native Android storage support is unavailable in this build.');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not read storage status.');
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

  Future<void> _select(int slot) async {
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<void>('selectVolume', {'slot': slot});
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
    _serverPasswordController.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = _status['usb1']?.toString() ?? 'Not selected';
    final second = _status['usb2']?.toString() ?? 'Not selected';
    final running = _status['running'] == true;
    final internalGranted = _status['internalStorageGranted'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('This device · Storage setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Set up the Android phone that will host HomeServer. Internal storage access is needed for shared folders such as Music, Movies, Pictures, DCIM and Download.',
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                internalGranted ? Icons.check_circle : Icons.folder_special,
                color: internalGranted ? Colors.green : null,
              ),
              title: const Text('Internal shared storage'),
              subtitle: Text(internalGranted
                  ? 'All-files access is enabled.'
                  : 'Android requires you to approve “Allow access to manage all files”.'),
              trailing: internalGranted
                  ? const Icon(Icons.verified)
                  : const Icon(Icons.chevron_right),
              onTap: _busy || internalGranted ? null : _requestInternalStorageAccess,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh permission status'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Native server password',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(_serverPasswordConfigured
                      ? 'A password verifier is saved on this device.'
                      : 'Set a password of at least 12 characters for remote access.'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _serverPasswordController,
                    obscureText: true,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'New server password',
                      helperText: 'Not uploaded or stored in plaintext.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _saveServerPassword,
                    child: Text(_serverPasswordConfigured
                        ? 'Update server password'
                        : 'Save server password'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'USB / SSD storage',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Select each USB partition once. Android remembers the folder permissions.'),
          const SizedBox(height: 12),
          _VolumeTile(title: 'USB Storage 1', value: first, onTap: _busy ? null : () => _select(1)),
          _VolumeTile(title: 'USB Storage 2', value: second, onTap: _busy ? null : () => _select(2)),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || (!internalGranted && first == 'Not selected' && second == 'Not selected')
                ? null
                : (running ? _stop : _start),
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            label: Text(running ? 'Stop local storage service' : 'Start local storage service'),
          ),
          const SizedBox(height: 20),
          const Text('Backend bridge token', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText(_token ?? 'Loading…'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _token == null ? null : () => Clipboard.setData(ClipboardData(text: _token!)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy token'),
            ),
          ),
          const Text(
            'Temporary compatibility setting for the current Termux backend. This token will no longer be needed once the native HomeServer API is enabled.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _VolumeTile extends StatelessWidget {
  const _VolumeTile({required this.title, required this.value, required this.onTap});
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.usb),
          title: Text(title),
          subtitle: Text(value),
          trailing: const Icon(Icons.folder_open),
          onTap: onTap,
        ),
      );
}