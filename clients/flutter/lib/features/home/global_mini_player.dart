import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/logging/app_logger.dart';
import '../../core/logging/diagnostic_observer.dart';
import '../../core/settings/app_settings.dart';
import '../media/persistent_audio_player.dart';
import '../media/persistent_mini_player.dart';
import 'app_wide_controls.dart';

/// Displays the active music session above every eligible app route.
class GlobalMiniPlayer extends StatefulWidget {
  const GlobalMiniPlayer({super.key});

  @override
  State<GlobalMiniPlayer> createState() => _GlobalMiniPlayerState();
}

class _GlobalMiniPlayerState extends State<GlobalMiniPlayer> {
  String? _lastLoggedState;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final player = PersistentAudioPlayer.instance;
    final controls = AppWideControlsController.instance;
    final observer = DiagnosticNavigatorObserver.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([
        settings,
        player,
        observer.settingsVisible,
        observer.dashboardVisible,
      ]),
      builder: (context, _) {
        final settingEnabled = settings.showMiniPlayer;
        final playerEligible = player.showMiniPlayer;
        // The player owns Now Playing visibility. Navigator observers can miss
        // nested-route pops, so do not use route visibility to decide whether
        // the mini-player returns after Now Playing is dismissed.
        final fullScreen = player.isFullScreen;
        final settingsRoute = observer.settingsVisible.value;
        final visible = settingEnabled &&
            playerEligible &&
            !fullScreen &&
            !settingsRoute;

        final signature = [
          'setting=$settingEnabled',
          'active=${player.isActive}',
          'music=${player.isMusic}',
          'hasItem=${player.currentItem != null}',
          'playing=${player.isPlaying}',
          'fullScreen=$fullScreen',
          'settingsRoute=$settingsRoute',
          'dashboard=${observer.dashboardVisible.value}',
          'controllerAttached=${controls.isAttached}',
          'openAction=${controls.openNowPlaying != null}',
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

        final bottom = observer.dashboardVisible.value ? 82.0 : 8.0;
        return Positioned(
          left: 14,
          right: 16,
          bottom: bottom + MediaQuery.paddingOf(context).bottom,
          child: PersistentMiniPlayer(
            player: player,
            onOpen: () => controls.openNowPlaying?.call(),
          ),
        );
      },
    );
  }
}
