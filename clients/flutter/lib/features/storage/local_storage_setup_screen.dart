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
      setState(() => _error = call.arguments?.toString() ?? 'Could not save storage permission.');
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
        _error = null;
        _busy = false;
      });
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Native Android storage support is unavailable in this build.');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not read storage status.');
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
      await _refresh();
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
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = _status['usb1']?.toString() ?? 'Not selected';
    final second = _status['usb2']?.toString() ?? 'Not selected';
    final running = _status['running'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('This device · USB storage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Use this screen on the Android phone running HomeServer and connected to your SSD. '
            'Grant each partition once; Android remembers the permissions.',
          ),
          const SizedBox(height: 16),
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
            onPressed: _busy || (first == 'Not selected' && second == 'Not selected') ? null : (running ? _stop : _start),
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
            'Keep this token private. Configure the HomeServer backend with this token in its private '
            'ssd-bridge-token.txt file. The bridge listens only on this device’s loopback address.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh), label: const Text('Refresh status')),
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
