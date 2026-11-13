import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/server_api.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const _storage = FlutterSecureStorage();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8000');

  bool _isConnecting = false;
  String? _message;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _restoreAddress();
  }

  Future<void> _restoreAddress() async {
    final saved = await _storage.read(key: 'last_server_address');
    if (!mounted || saved == null) return;
    final uri = Uri.tryParse(
      saved.startsWith('http://') || saved.startsWith('https://')
          ? saved
          : 'http://$saved',
    );
    if (uri == null) return;
    _addressController.text = uri.host;
    if (uri.hasPort) _portController.text = uri.port.toString();
  }

  Future<void> _connect() async {
    final host = _addressController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() {
        _connected = false;
        _message = 'Enter a valid server address and port.';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connected = false;
      _message = null;
    });

    try {
      final api = ServerApi(baseUrl: '$host:$port');
      final healthy = await api.checkHealth();
      if (!healthy) throw StateError('Server health check failed.');

      await _storage.write(
        key: 'last_server_address',
        value: '$host:$port',
      );

      if (!mounted) return;
      setState(() {
        _connected = true;
        _message = 'Server is reachable. Authentication setup is next.';
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout
            ? 'Connection timed out. Check the address, port, and network.'
            : 'Could not reach the server. Check the address and port.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Unexpected connection error.');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 52,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'HomeServer',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to your server and manage it from one place.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _addressController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    hintText: '192.168.1.10 or example.com',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isConnecting ? null : _connect,
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_isConnecting ? 'Connecting…' : 'Connect'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _connected
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Connection check only: secure login and file operations '
                  'will be enabled after the backend API contract is verified. '
                  'Use HTTPS for connections over untrusted networks.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
