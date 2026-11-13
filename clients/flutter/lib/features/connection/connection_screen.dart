import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/server_api.dart';
import '../home/home_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const _storage = FlutterSecureStorage();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8000');
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();

  bool _isConnecting = false;
  bool _obscurePassword = true;
  String? _message;

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
    _usernameController.text =
        await _storage.read(key: 'last_server_username') ?? 'admin';
    _passwordController.text =
        await _storage.read(key: 'last_server_password') ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    final host = _addressController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        username.isEmpty ||
        password.isEmpty) {
      setState(() => _message = 'Enter the server, port, username, and password.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _message = null;
    });

    try {
      final api = ServerApi(
        baseUrl: '$host:$port',
        username: username,
        password: password,
      );
      await api.authenticate();

      await _storage.write(key: 'last_server_address', value: '$host:$port');
      await _storage.write(key: 'last_server_username', value: username);
      await _storage.write(key: 'last_server_password', value: password);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(api: api),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _message = status == 401
            ? 'Incorrect username or password.'
            : status == 403
                ? 'The server denied access.'
                : status == 404
                    ? 'File API not found on this server.'
                    : error.type == DioExceptionType.connectionTimeout ||
                            error.type == DioExceptionType.receiveTimeout
                        ? 'Connection timed out. Check the address, port, and network.'
                        : 'Could not connect. Check the server address and credentials.';
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Unexpected connection error.');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
                Icon(Icons.dns_rounded, size: 52, color: colorScheme.primary),
                const SizedBox(height: 20),
                Text(
                  'HomeServer',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to your server and manage your files.',
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
                const SizedBox(height: 14),
                TextField(
                  controller: _usernameController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                    ),
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
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Use the admin username and the password configured on your server. '
                  'Use HTTPS on untrusted networks.',
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
