import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/logging/app_logger.dart';
import '../../core/logging/diagnostic_observer.dart';
import '../../core/settings/app_settings.dart';
import '../media/persistent_audio_player.dart';
import '../media/persistent_mini_player.dart';
import 'app_wide_controls.dart';

/// Owns mini-player visibility independently from the shortcut overlay and
/// from individual page lifecycles. The audio engine is never recreated here.
class GlobalMiniPlayer extends StatefulWidget {
  const GlobalMiniPlayer({super.key});

  @override
  State<GlobalMiniPlayer> createState() => _GlobalMiniPlayerState();
}

class _GlobalMiniPlayerState extends State<GlobalMiniPlayer> {
  final _settings = AppSettings.instance;
  final _player = PersistentAudioPlayer.instance;
  final _controls = AppWideControlsController.instance;
  final _observer = DiagnosticNavigatorObserver.instance;

  bool _dismissed = false;
  bool _lastPlaying = false;
  String? _lastLoggedState;

  @override
  void initState() {
    super.initState();
    _lastPlaying = _player.isPlaying;
    _player.addListener(_playerChanged);
  }

  void _playerChanged() {
    final playing = _player.isPlaying;
    if (playing && !_lastPlaying && _dismissed && mounted) {
      setState(() => _dismissed = false);
    }
    _lastPlaying = playing;
  }

  @override
  void dispose() {
    _player.removeListener(_playerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _settings,
        _player,
        _controls,
        _observer.controlsVisible,
        _observer.dashboardVisible,
      ]),
      builder: (context, _) {
        final settingEnabled = _settings.showMiniPlayer;
        final playerEligible = _player.showMiniPlayer;
        final controlsAttached = _controls.isAttached;
        final routeVisible = _observer.controlsVisible.value;
        final openActionAvailable = _controls.openNowPlaying != null;
        final visible = settingEnabled &&
            playerEligible &&
            controlsAttached &&
            routeVisible &&
            openActionAvailable &&
            !_dismissed;

        final signature = [
          'setting=$settingEnabled',
          'active=${_player.isActive}',
          'music=${_player.isMusic}',
          'hasItem=${_player.currentItem != null}',
          'playing=${_player.isPlaying}',
          'attached=$controlsAttached',
          'routeVisible=$routeVisible',
          'dashboard=${_observer.dashboardVisible.value}',
          'openAction=$openActionAvailable',
          'dismissed=$_dismissed',
          'visible=$visible',
        ].join('|');
        if (_lastLoggedState != signature) {
          _lastLoggedState = signature;
          unawaited(AppLogger.info(
            'Global mini-player state',
            fields: {'state': signature},
          ));
        }

        if (!visible) return const SizedBox.shrink();

        final bottom = _observer.dashboardVisible.value ? 82.0 : 8.0;
        return Positioned(
          left: 14,
          right: 16,
          bottom: bottom + MediaQuery.paddingOf(context).bottom,
          child: PersistentMiniPlayer(
            player: _player,
            onOpen: () => _controls.openNowPlaying?.call(),
            onDismiss: () {
              if (!_player.isPlaying) setState(() => _dismissed = true);
            },
          ),
        );
      },
    );
  }
}
