import 'dart:async';
import '../../core/widgets/pocketlink_app_bar.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/logging/app_logger.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../media/discover/discover_screen.dart';
import '../home/home_screen.dart';
import '../storage/local_storage_setup_screen.dart';
import '../settings/settings_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.autoConnect = true});

  final bool autoConnect;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const _storage = FlutterSecureStorage();
  static const _profilesKey = 'server_profiles';
  final _serverNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8000');
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();

  // This collection is mutated when servers are added, removed, or reordered.
  List<Map<String, String>> _profiles = <Map<String, String>>[];
  bool _isConnecting = false;
  bool _isRestoringSession = true;
  CancelToken? _authenticationCancelToken;
  String? _connectingProfileId;
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
          'name': item['name']?.toString() ?? '',
          'username': item['username']?.toString() ?? 'admin',
        }).where((item) => item['id']!.isNotEmpty && item['address']!.isNotEmpty)
          .toList(growable: true);
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
        // Prefer the last successfully connected server; fall back to the
        // most recently used saved profile if legacy session data is absent.
        var selectedProfile = _profiles.first;
        for (final profile in _profiles) {
          if (profile['address'] == saved && profile['username'] == username) {
            selectedProfile = profile;
            break;
          }
        }
        await _selectProfile(selectedProfile, connect: false);
        if (widget.autoConnect && _passwordController.text.isNotEmpty) {
          await _openSavedSession();
        }
      } else if (saved != null) {
        _applyAddress(saved);
        _usernameController.text = username;
        _passwordController.text = password ?? '';
      }
    } catch (error) {
      await AppLogger.warning(
        'Could not restore saved server session',
        fields: {'error_type': error.runtimeType.toString()},
      );
    } finally {
      if (mounted && _isRestoringSession) {
        setState(() => _isRestoringSession = false);
      }
    }
  }

  /// Opens a saved session without a startup network probe.
  ///
  /// ServerApi attaches the saved Basic Auth credentials to every request, so
  /// the dashboard can render immediately and normal data requests determine
  /// whether the server is reachable.
  Future<void> _openSavedSession() async {
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
      return;
    }

    late final ServerApi api;
    try {
      api = ServerApi(
        baseUrl: '$host:$port',
        username: username,
        password: password,
      );
    } catch (error) {
      await AppLogger.warning(
        'Could not restore saved server client',
        fields: {'error_type': error.runtimeType.toString()},
      );
      return;
    }

    if (!mounted) {
      api.close();
      return;
    }
    setState(() {
      _isRestoringSession = false;
      _message = null;
    });
    await AppLogger.info(
      'Saved server session restored; startup network probe skipped',
      fields: {'host': host, 'port': port},
    );
    await _openDashboard(api);
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
    _serverNameController.text = profile['name'] ?? '';
    _obscurePassword = true;
    _usernameController.text = profile['username']!;
    _passwordController.text =
        await _storage.read(key: 'server_password_${profile['id']}') ?? '';
    if (!mounted) return;
    setState(() => _message = null);
    if (connect && _passwordController.text.isNotEmpty) await _connect();
  }

  Future<void> _addServer() async {
    _obscurePassword = true;
    _serverNameController.clear();
    _addressController.clear();
    _portController.text = '8000';
    _usernameController.text = 'admin';
    _passwordController.clear();
    setState(() => _message = null);
  }

  String _networkLabel(String address) {
    final parsed = Uri.tryParse(address.contains('://') ? address : 'http://$address');
    final ip = parsed == null ? null : InternetAddress.tryParse(parsed.host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return 'LAN';
    final octets = ip.rawAddress;
    if (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) return 'Tailscale';
    if ((octets[0] == 192 && octets[1] == 168) || octets[0] == 10) return 'LAN';
    return 'LAN';
  }

  Future<void> _editProfile(Map<String, String> profile) async {
    await _selectProfile(profile, connect: false);
    if (mounted) setState(() => _message = 'Edit the server details, then tap Connect & save server.');
  }

  Future<void> _connectProfile(Map<String, String> profile) async {
    if (_isConnecting || _connectingProfileId != null) return;
    setState(() { _connectingProfileId = profile['id']; _message = null; });
    try {
      await _selectProfile(profile, connect: false);
      if (_passwordController.text.isEmpty) {
        if (mounted) setState(() {
          _message = 'Enter the password for this saved server, then connect.';
          _connectingProfileId = null;
        });
        return;
      }
      await _connect();
    } finally {
      if (mounted) setState(() => _connectingProfileId = null);
    }
  }

  void _cancelConnection() {
    final cancelToken = _authenticationCancelToken;
    if (cancelToken == null || cancelToken.isCancelled) return;
    cancelToken.cancel('Connection cancelled by user.');
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
    final lastAddress = await _storage.read(key: 'last_server_address');
    final lastUsername = await _storage.read(key: 'last_server_username') ?? 'admin';
    if (lastAddress == profile['address'] &&
        lastUsername == profile['username']) {
      await _storage.delete(key: 'last_server_address');
      await _storage.delete(key: 'last_server_username');
      await _storage.delete(key: 'last_server_password');
    }
    await _persistProfiles();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openHost() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LocalStorageSetupScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _openDiscover() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: PocketLinkRouteNames.standaloneDiscover,
        ),
        builder: (_) => const DiscoverScreen(),
      ),
    );
  }

  Future<void> _connect({bool restoringSession = false}) async {
    // Ignore repeated taps while an authentication or navigation attempt is active.
    if (_isConnecting) return;
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
    } on FormatException catch (error) {
      await AppLogger.warning('Connection address validation failed');
      if (mounted) setState(() {
        _message = error.message;
        _isConnecting = false;
      });
      return;
    } catch (error, stack) {
      await AppLogger.error('Connection client initialization failed', error: error, stackTrace: stack);
      if (mounted) setState(() {
        _message = 'Could not initialize the server connection. Check the address and try again.';
        _isConnecting = false;
      });
      return;
    }

    var authenticated = false;
    final authenticationCancelToken = CancelToken();
    _authenticationCancelToken = authenticationCancelToken;
    try {
      await api.authenticate(cancelToken: authenticationCancelToken).timeout(
        Duration(seconds: restoringSession ? 20 : 55),
        onTimeout: () {
          authenticationCancelToken.cancel('Authentication deadline exceeded.');
          throw TimeoutException('Server authentication timed out.');
        },
      );
      await AppLogger.info('Server authentication succeeded', fields: {'host': host, 'port': port});
      authenticated = true;
    } on DioException catch (error) {
      if (authenticationCancelToken.isCancelled ||
          error.type == DioExceptionType.cancel) {
        if (mounted) {
          setState(() {
            _message = 'Connection cancelled.';
            _isConnecting = false;
          });
        }
        return;
      }
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
          _message = 'The server took too long to respond. Check that PocketLink is running, then try again.';
          _isConnecting = false;
        });
      }
      return;
    } catch (error, stack) {
      await AppLogger.error('Connection initialization failed', error: error, stackTrace: stack);
      if (mounted) {
        setState(() {
          _message = 'Could not initialize the server connection. Check the address and try again.';
          _isConnecting = false;
        });
      }
      return;
    } finally {
      if (identical(_authenticationCancelToken, authenticationCancelToken)) {
        _authenticationCancelToken = null;
        if (mounted) setState(() {});
      }
      if (!authenticated) api.close();
    }

    if (!mounted) {
      api.close();
      return;
    }
    final id = _profileId(address, username);
    final profile = {
      'id': id,
      'address': address,
      'name': _serverNameController.text.trim(),
      'username': username,
    };
    _profiles.removeWhere((item) => item['id'] == id);
    _profiles.insert(0, profile);

    // A secure-storage write failure must not turn a successful connection
    // into a misleading connection error or block access to the server.
    try {
      await AppLogger.info('Saving authenticated server profile');
      await () async {
        await _storage.write(key: 'server_password_$id', value: password);
        await _persistProfiles();
        await _storage.write(key: 'last_server_address', value: address);
        await _storage.write(key: 'last_server_username', value: username);
        await _storage.write(key: 'last_server_password', value: password);
      }().timeout(const Duration(seconds: 5));
      await AppLogger.info('Server profile saved');
    } on TimeoutException {
      await AppLogger.warning('Saving server profile timed out');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected. Saving this server is taking too long; you can still continue.')),
        );
      }
    } catch (error, stack) {
      await AppLogger.error('Saving server profile failed', error: error, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected, but this server could not be saved securely.')),
        );
      }
    }

    if (!mounted) {
      api.close();
      return;
    }
    setState(() {
      if (restoringSession) _isRestoringSession = false;
    });
    await _openDashboard(api);
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _openDashboard(ServerApi api) async {
    if (!mounted) {
      api.close();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: PocketLinkAppBar.dashboardRouteName,
        ),
        builder: (_) => HomeScreen(
          api: api,
          serverName: _serverNameController.text.trim(),
          onReturnToConnection: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const ConnectionScreen(autoConnect: false),
              ),
              (route) => false,
            );
          },
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData? icon,
    Widget? suffixIcon,
  }) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: colors.outlineVariant.withValues(alpha: 0.58),
        width: 1,
      ),
    );
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 19, color: colors.onSurfaceVariant),
      prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 48),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colors.surfaceContainerLow.withValues(alpha: 0.76),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFF536DFE), width: 1.2),
      ),
    );
  }

  @override
  void dispose() {
    _serverNameController.dispose();
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

    final media = MediaQuery.of(context);

    if (_isRestoringSession) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Connecting to your server…',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        title: const Text('PocketLink'),
        showHome: false,
        actions: [
          PocketLinkAppBarAction(
            label: 'Settings',
            icon: Icons.settings_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          PocketLinkAppBarAction(
            label: 'Show Discover: ${AppSettings.instance.showDiscoverOnWelcome ? 'On' : 'Off'}',
            icon: AppSettings.instance.showDiscoverOnWelcome
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            onPressed: () async {
              await AppSettings.instance.setShowDiscoverOnWelcome(
                !AppSettings.instance.showDiscoverOnWelcome,
              );
              if (mounted) setState(() {});
            },
          ),
          PocketLinkAppBarAction(
            label: 'Diagnostics & logs',
            icon: Icons.bug_report_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, media.padding.top + kToolbarHeight + 4, 20, 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 'connect', label: Text('Connect')),
                    const ButtonSegment(value: 'host', label: Text('Host')),
                    if (AppSettings.instance.showDiscoverOnWelcome)
                      const ButtonSegment(value: 'discover', label: Text('Discover')),
                  ],
                  selected: const {'connect'},
                  onSelectionChanged: _isConnecting ? null : (selection) {
                    switch (selection.first) {
                      case 'host': unawaited(_openHost());
                      case 'discover': unawaited(_openDiscover());
                    }
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      leading: const CircleAvatar(child: Icon(Icons.dns_rounded)),
                      title: Text(
                        (profile['name'] ?? '').trim().isNotEmpty
                            ? profile['name']!.trim()
                            : profile['address']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Row(children: [
                        Expanded(child: Text('${profile['address']} • ${profile['username']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.62)),
                          ),
                          child: Text(_networkLabel(profile['address']!),
                            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                        ),
                      ]),
                      onTap: _isConnecting ? null : () => _connectProfile(profile),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_connectingProfileId == profile['id'])
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _editProfile(profile);
                            if (value == 'delete') _removeProfile(profile);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ]),
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
                    'Add one or more PocketLink servers and switch between them anytime.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                ],
                TextField(
                  controller: _serverNameController,
                  textCapitalization: TextCapitalization.words,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(hint: 'Server name (optional)', icon: Icons.edit_location_alt_outlined),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addressController,
                        keyboardType: TextInputType.url,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: _inputDecoration(
                          hint: 'Server address',
                          icon: Icons.language,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 112,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        textInputAction: TextInputAction.next,
                        textAlign: TextAlign.start,
                        maxLength: 5,
                        buildCounter: (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => null,
                        decoration: _inputDecoration(
                          hint: 'Port',
                          icon: null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  autocorrect: false,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(hint: 'Username', icon: Icons.person_outline),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _connect(),
                  decoration: _inputDecoration(
                    hint: 'Password',
                    icon: Icons.lock_outline,
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
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
                    ),
                    if (_authenticationCancelToken != null) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _authenticationCancelToken!.isCancelled
                            ? null
                            : _cancelConnection,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel'),
                      ),
                    ],
                  ],
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
          ),
        ],
      ),
    );
  }
}
