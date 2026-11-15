import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/server_api.dart';
import '../../core/logging/app_logger.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../home/home_screen.dart';
import '../storage/local_storage_setup_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const _storage = FlutterSecureStorage();
  static const _profilesKey = 'server_profiles';
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8000');
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();

  List<Map<String, String>> _profiles = const [];
  bool _isConnecting = false;
  bool _obscurePassword = true;
  String? _message;

  String _profileId(String address, String username) =>
      base64Url.encode(utf8.encode('$address|$username')).replaceAll('=', '');

  @override
  void initState() {
    super.initState();
    _restoreAddress();
  }

  Future<void> _restoreAddress() async {
    try {
      final raw = await _storage.read(key: _profilesKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is List) {
        _profiles = decoded.whereType<Map>().map((item) => {
          'id': item['id']?.toString() ?? '',
          'address': item['address']?.toString() ?? '',
          'username': item['username']?.toString() ?? 'admin',
        }).where((item) => item['id']!.isNotEmpty && item['address']!.isNotEmpty)
          .toList(growable: true);
      }
    } catch (_) {
      _profiles = [];
    }

    // Migrate the previous single-server credentials without losing them.
    final saved = await _storage.read(key: 'last_server_address');
    final username = await _storage.read(key: 'last_server_username') ?? 'admin';
    final password = await _storage.read(key: 'last_server_password');
    if (saved != null && password != null) {
      final id = _profileId(saved, username);
      if (!_profiles.any((profile) => profile['id'] == id)) {
        _profiles.add({'id': id, 'address': saved, 'username': username});
        await _storage.write(key: 'server_password_$id', value: password);
        await _persistProfiles();
      }
    }

    if (!mounted) return;
    if (_profiles.isNotEmpty) {
      await _selectProfile(_profiles.first, connect: false);
    } else if (saved != null) {
      _applyAddress(saved);
      _usernameController.text = username;
      _passwordController.text = password ?? '';
    }
    if (mounted) setState(() {});
  }

  void _applyAddress(String address) {
    final uri = Uri.tryParse(
      address.startsWith('http://') || address.startsWith('https://')
          ? address
          : 'http://$address',
    );
    if (uri == null) return;
    _addressController.text = uri.host;
    _portController.text = uri.hasPort ? uri.port.toString() : '8000';
  }

  Future<void> _persistProfiles() async {
    await _storage.write(key: _profilesKey, value: jsonEncode(_profiles));
  }

  Future<void> _selectProfile(
    Map<String, String> profile, {
    bool connect = true,
  }) async {
    _applyAddress(profile['address']!);
    _usernameController.text = profile['username']!;
    _passwordController.text =
        await _storage.read(key: 'server_password_${profile['id']}') ?? '';
    if (!mounted) return;
    setState(() => _message = null);
    if (connect && _passwordController.text.isNotEmpty) await _connect();
  }

  Future<void> _addServer() async {
    _addressController.clear();
    _portController.text = '8000';
    _usernameController.text = 'admin';
    _passwordController.clear();
    setState(() => _message = null);
  }

  Future<void> _removeProfile(Map<String, String> profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove server?'),
        content: Text('Remove ${profile['address']} from saved servers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _profiles.removeWhere((item) => item['id'] == profile['id']);
    await _storage.delete(key: 'server_password_${profile['id']}');
    await _persistProfiles();
    if (!mounted) return;
    setState(() {});
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

    unawaited(AppLogger.info('Connection attempt started', fields: {'host': host, 'port': port, 'username': username}));
    setState(() {
      _isConnecting = true;
      _message = null;
    });

    final address = '$host:$port';
    late final ServerApi api;
    try {
      api = ServerApi(
        baseUrl: address,
        username: username,
        password: password,
      );
      await api.authenticate().timeout(const Duration(seconds: 15));
      await AppLogger.info('Server authentication succeeded', fields: {'host': host, 'port': port});
    } on DioException catch (error) {
      await AppLogger.warning('Server authentication failed', fields: {'host': host, 'port': port, 'type': error.type.name, 'status': error.response?.statusCode});
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _message = status == 401
            ? 'The server rejected these credentials for storage access. Re-enter the current server admin password. The SAF bridge token is separate.'
            : status == 403
                ? 'The server denied access.'
                : status == 404
                    ? 'File API not found on this server.'
                    : error.type == DioExceptionType.connectionTimeout ||
                            error.type == DioExceptionType.receiveTimeout
                        ? 'Connection timed out. Check the address, port, and network.'
                        : error.type == DioExceptionType.connectionError
                            ? 'Could not reach the server. Check that it is running and that the address, port, and network are correct.'
                            : error.type == DioExceptionType.badCertificate
                                ? 'The server certificate could not be verified. Check the server HTTPS certificate.'
                                : 'Could not connect. Check the server address and credentials.';
        _isConnecting = false;
      });
      return;
    } on TimeoutException {
      await AppLogger.warning('Server authentication timed out', fields: {'host': host, 'port': port});
      if (mounted) {
        setState(() {
          _message = 'The server took too long to respond. Check that HomeServer is running, then try again.';
          _isConnecting = false;
        });
      }
      return;
    } on FormatException catch (error) {
      await AppLogger.warning('Connection address validation failed');
      if (mounted) setState(() {
        _message = error.message;
        _isConnecting = false;
      });
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not initialize the server connection. Check the address and try again.';
          _isConnecting = false;
        });
      }
      return;
    }

    if (!mounted) return;
    final id = _profileId(address, username);
    final profile = {'id': id, 'address': address, 'username': username};
    _profiles.removeWhere((item) => item['id'] == id);
    _profiles.insert(0, profile);

    // A secure-storage write failure must not turn a successful connection
    // into a misleading connection error or block access to the server.
    try {
      await () async {
        await _storage.write(key: 'server_password_$id', value: password);
        await _persistProfiles();
        await _storage.write(key: 'last_server_address', value: address);
        await _storage.write(key: 'last_server_username', value: username);
        await _storage.write(key: 'last_server_password', value: password);
      }().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected. Saving this server is taking too long; you can still continue.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected, but this server could not be saved securely.')),
        );
      }
    }

    if (!mounted) return;
    setState(() {});
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: api)),
      );
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
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeServer'),
        actions: [
          IconButton(
            tooltip: 'Diagnostics & logs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
            ),
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: 'Add server',
            onPressed: _isConnecting ? null : _addServer,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_profiles.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text('Your servers',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                      ),
                      TextButton.icon(
                        onPressed: _isConnecting ? null : _addServer,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._profiles.map((profile) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.dns_rounded),
                      ),
                      title: Text(profile['address']!),
                      subtitle: Text(profile['username']!),
                      onTap: _isConnecting
                          ? null
                          : () => _selectProfile(profile),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'remove') _removeProfile(profile);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove server'),
                          ),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text('Server details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 12),
                ] else ...[
                  Icon(Icons.dns_rounded, size: 52, color: colors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Connect to your server',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add one or more HomeServer instances and switch between them anytime.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                ],
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
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _isConnecting ? null : _connect,
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_isConnecting ? 'Connecting…' : 'Connect & save server'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _isConnecting
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LocalStorageSetupScreen(),
                            ),
                          ),
                  icon: const Icon(Icons.dns_outlined),
                  label: const Text('Set up this phone as a HomeServer'),
                ),
                const SizedBox(height: 18),
                Text(
                  'Saved passwords are kept in Android secure storage. Use HTTPS on untrusted networks.',
                  style: theme.textTheme.bodySmall,
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
