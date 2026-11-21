import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/pocketlink_app_bar.dart';
import 'widgets/host_section_destination.dart';
import 'widgets/host_media_scan_card.dart';
import 'widgets/host_server_password_card.dart';
import 'widgets/host_backend_bridge_token_card.dart';
import 'widgets/host_storage_service_card.dart';
import 'widgets/host_setup_section_title.dart';
import 'widgets/host_device_permissions_card.dart';
import 'widgets/host_status_card.dart';
import 'widgets/host_quick_actions_card.dart';
import 'widgets/host_device_intro_card.dart';
import 'widgets/host_action_feedback_section.dart';
import 'widgets/host_external_storage_section.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/liquid_glass_pill.dart';

import '../diagnostics/diagnostics_screen.dart';
import '../about/about_screen.dart';

class LocalStorageSetupScreen extends StatefulWidget {
  const LocalStorageSetupScreen({this.onHome, super.key});

  final VoidCallback? onHome;

  @override
  State<LocalStorageSetupScreen> createState() => _LocalStorageSetupScreenState();
}

class _LocalStorageSetupScreenState extends State<LocalStorageSetupScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('pocketlink/saf');
  int _selectedSectionIndex = 0;
  final PageController _sectionPageController = PageController();
  Map<String, dynamic> _status = const {};
  String? _token;
  final _serverPasswordController = TextEditingController();
  bool _serverPasswordConfigured = false;
  bool _obscureServerPassword = true;
  bool _obscureBridgeToken = true;
  bool _refreshingStatus = false;
  DateTime? _lastStatusRefreshAt;
  bool _statusLoaded = false;
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
        _statusLoaded = true;
        _lastStatusRefreshAt = DateTime.now();
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
      if (mounted) {
        setState(() {
          _statusLoaded = true;
          _error = 'Native Android storage support is unavailable in this build.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _statusLoaded = true;
          _error = error.message ?? 'Could not read storage status.';
        });
      }
    }
  }

  Future<void> _refreshDeviceStatus() async {
    if (_refreshingStatus || _busy) return;
    setState(() {
      _refreshingStatus = true;
      _error = null;
    });
    try {
      await _refresh();
    } finally {
      if (mounted) setState(() => _refreshingStatus = false);
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

  String? _formatScanTimestamp(dynamic value) {
    final milliseconds = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (milliseconds == null || milliseconds <= 0) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '${date.day}/${date.month}/${date.year} · $hour:$minute $period';
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
        final status = Map<String, dynamic>.from(jsonDecode(initial) as Map);
        setState(() {
          _mediaScanStatus = status;
          _scanningMedia = status['state'] == 'scanning';
        });
        // Poll only while this user-requested scan is active; no permanent timer.
        if (_scanningMedia) await _watchMediaScan();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Native server password saved securely.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not save server password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyBridgeToken() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backend bridge token copied.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _requestBackgroundAccess() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<bool>('requestBackgroundAccess');
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() {
        _busy = false;
        _error = error.message ?? 'Could not open background activity settings.';
      });
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
          _error = 'Enable “Allow access to manage all files” for PocketLink, return here, then refresh status.';
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

  Future<void> _chooseStorageFolder() => _select(
        'usb-manual-${DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0').substring(0, 16)}',
      );

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
    _sectionPageController.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  void _selectHostSection(int index) {
    if (_selectedSectionIndex == index) return;
    setState(() => _selectedSectionIndex = index);
    _sectionPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final legacySelected = (_status['usb1'] != null && _status['usb1'] != 'Not selected') ||
        (_status['usb2'] != null && _status['usb2'] != 'Not selected');
    final running = _status['running'] == true;
    final internalGranted = _status['internalStorageGranted'] == true;
    final backgroundGranted = _status['backgroundAccessGranted'] == true;
    final requiredAccessReady = _statusLoaded && internalGranted;
    final selectedVolumeCount = _discoveredVolumes.where((v) => v['selected'] == true).length;
    final canStart = internalGranted || legacySelected || selectedVolumeCount > 0;
    final skippedScanItems = (_mediaScanStatus['skipped'] as num?)?.toInt() ?? 0;
    final completedScanAt = _formatScanTimestamp(_mediaScanStatus['last_completed_at']);

    final apiRunning = _status['apiRunning'] == true;
    final bridgeRunning = _status['bridgeRunning'] == true;
    final detectedVolumeCount = _discoveredVolumes.length;
    final usbStatus = selectedVolumeCount > 0
        ? '$selectedVolumeCount ready'
        : detectedVolumeCount > 0
            ? '$detectedVolumeCount detected · access needed'
            : 'Not connected';

    String statusCheckedLabel() {
      final checkedAt = _lastStatusRefreshAt;
      if (checkedAt == null) return 'Status has not been checked yet';
      final date = checkedAt.toLocal();
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour < 12 ? 'AM' : 'PM';
      return 'Updated ${date.day}/${date.month} · $hour:$minute $period';
    }

    final hostSections = <Widget>[
      const HostDeviceIntroCard(),
      const SizedBox(height: 14),
      HostStatusCard(
        statusLoaded: _statusLoaded,
        running: running,
        apiRunning: apiRunning,
        serverPasswordConfigured: _serverPasswordConfigured,
        bridgeRunning: bridgeRunning,
        internalGranted: internalGranted,
        usbStatus: usbStatus,
        selectedVolumeCount: selectedVolumeCount,
        detectedVolumeCount: detectedVolumeCount,
        refreshing: _refreshingStatus,
        busy: _busy,
        statusCheckedLabel: statusCheckedLabel(),
        onRefresh: _refreshDeviceStatus,
      ),
      const SizedBox(height: 14),
      HostQuickActionsCard(
        onManageStorage: () => setState(() => _selectedSectionIndex = 1),
        onSecuritySettings: () => setState(() => _selectedSectionIndex = 2),
        onDiagnostics: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DiagnosticsScreen(),
          ),
        ),
      ),
    ];
    final securitySections = <Widget>[
      const SizedBox(height: 22),
      const HostSetupSectionTitle(
        title: 'Server security',
        subtitle: 'Set the password used by remote clients to connect.',
      ),
      const SizedBox(height: 10),
      HostServerPasswordCard(
        controller: _serverPasswordController,
        configured: _serverPasswordConfigured,
        busy: _busy,
        obscurePassword: _obscureServerPassword,
        onToggleVisibility: () => setState(
          () => _obscureServerPassword = !_obscureServerPassword,
        ),
        onSave: _saveServerPassword,
      ),
    ];
    final permissionSections = <Widget>[
      const SizedBox(height: 24),
      HostDevicePermissionsCard(
        statusLoaded: _statusLoaded,
        requiredAccessReady: requiredAccessReady,
        internalGranted: internalGranted,
        backgroundGranted: backgroundGranted,
        busy: _busy,
        refreshingStatus: _refreshingStatus,
        onRequestInternalStorageAccess: _requestInternalStorageAccess,
        onRequestBackgroundAccess: _requestBackgroundAccess,
        onRefresh: _refreshDeviceStatus,
      ),
    ];
    final serviceSections = <Widget>[
      HostStorageServiceCard(
        running: running,
        canStart: canStart,
        busy: _busy,
        onStart: _start,
        onStop: _stop,
      ),
    ];
    final mediaSections = <Widget>[
          const SizedBox(height: 24),
          const HostSetupSectionTitle(
            title: 'Device media & files',
            subtitle: 'Index photos, videos, music and searchable files in the background.',
          ),
          const SizedBox(height: 10),
          HostMediaScanCard(
            status: _mediaScanStatus,
            scanning: _scanningMedia,
            skippedItems: skippedScanItems,
            completedAt: completedScanAt,
            busy: _busy,
            onScan: _scanMediaAndFiles,
          ),
    ];
    final feedbackSections = <Widget>[
      HostActionFeedbackSection(busy: _busy, error: _error),
    ];
    final tokenSections = <Widget>[
          const SizedBox(height: 24),
          const HostSetupSectionTitle(
            title: 'Backend bridge',
            subtitle: 'Authentication for the Termux backend to access Android storage.',
          ),
          const SizedBox(height: 10),
          HostBackendBridgeTokenCard(
            token: _token,
            statusLoaded: _statusLoaded,
            obscureToken: _obscureBridgeToken,
            onToggleVisibility: () => setState(
              () => _obscureBridgeToken = !_obscureBridgeToken,
            ),
            onCopy: _copyBridgeToken,
          ),
    ];

    Widget sectionList(BuildContext layoutContext, String storageKey, List<Widget> sections) => ListView(
      key: PageStorageKey<String>(storageKey),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        LayoutInsetsScope.of(layoutContext).bottomClearance,
      ),
      children: sections,
    );

    final activeMiniPlayer =
        LayoutInsetsScope.maybeOf(context)?.hasActiveMiniPlayer ?? false;
    final bottomSystemInset = MediaQuery.paddingOf(context).bottom;
    return PocketLinkScaffold(
      hasFloatingNavBar: true,
      hasActiveMiniPlayer: activeMiniPlayer,
      child: Scaffold(
      extendBody: true,
      appBar: PocketLinkAppBar(
        title: const Text('Host PocketLink'),
        onHome: widget.onHome,
        showHome: false,
        leadingWidth: 54,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: SizedBox.square(
            dimension: 38,
            child: GlassCircleButton(
              tooltip: 'Back',
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  widget.onHome?.call();
                }
              },
              child: const Icon(Icons.arrow_back_rounded, size: 18),
            ),
          ),
        ),
        actions: [
          PocketLinkAppBarAction(
            label: 'Return to Client / Home',
            icon: Icons.home_rounded,
            onPressed: () => PocketLinkAppBar.goToDashboard(context),
          ),
          PocketLinkAppBarAction(
            label: 'About PocketLink',
            icon: Icons.info_outline_rounded,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
          PocketLinkAppBarAction(
            label: 'Logs & diagnostics',
            icon: Icons.article_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DiagnosticsScreen(),
              ),
            ),
          ),
        ],
      ),

      body: Builder(
        builder: (layoutContext) => PageView(
        controller: _sectionPageController,
        onPageChanged: (index) {
          if (_selectedSectionIndex != index) {
            setState(() => _selectedSectionIndex = index);
          }
        },
        children: [
          sectionList(layoutContext, 'host-overview', [
            ...hostSections,
            ...serviceSections,
            ...feedbackSections,
          ]),
          sectionList(layoutContext, 'host-storage', [
            ...permissionSections,
            HostExternalStorageSection(
              volumes: _discoveredVolumes,
              selectedVolumeCount: selectedVolumeCount,
              detectedVolumeCount: detectedVolumeCount,
              busy: _busy,
              refreshing: _refreshingStorage,
              onRefresh: _refreshStorage,
              onChooseFolder: _chooseStorageFolder,
              onSelectVolume: _select,
            ),
            ...mediaSections,
            ...feedbackSections,
          ]),
          sectionList(layoutContext, 'host-security', [
            ...securitySections,
            ...tokenSections,
            ...feedbackSections,
          ]),
        ],
      ),
      ),
      bottomNavigationBar: SizedBox(
        height: 64 + bottomSystemInset + 12,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomSystemInset + 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SizedBox(
                key: const ValueKey<String>('host-section-dock'),
                height: 64,
                width: double.infinity,
                child: SmokedGlassSurface(
                  radius: BorderRadius.circular(34),
                  child: Row(
                    children: [
                      HostSectionDestination(
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard_rounded,
                        label: 'Overview',
                        selected: _selectedSectionIndex == 0,
                        onTap: () => _selectHostSection(0),
                      ),
                      HostSectionDestination(
                        icon: Icons.devices_outlined,
                        selectedIcon: Icons.devices_rounded,
                        label: 'Device',
                        selected: _selectedSectionIndex == 1,
                        onTap: () => _selectHostSection(1),
                      ),
                      HostSectionDestination(
                        icon: Icons.lock_outline_rounded,
                        selectedIcon: Icons.lock_rounded,
                        label: 'Security',
                        selected: _selectedSectionIndex == 2,
                        onTap: () => _selectHostSection(2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
