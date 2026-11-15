import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/network/server_api.dart';

class MediaQueueItem {
  const MediaQueueItem({required this.title, required this.path, this.volume, this.localPath});

  final String title;
  final String path;
  final String? volume;
  final String? localPath;
}

/// App-scoped owner for the native media engine.
///
/// Screens may come and go; the Player remains alive until the app process ends.
class PersistentAudioPlayer extends ChangeNotifier {
  PersistentAudioPlayer._() {
    player = Player();
    if (defaultTargetPlatform == TargetPlatform.android) {
      _mediaChannel.setMethodCallHandler(_handleMediaCommand);
    }
    _playlistSubscription = player.stream.playlist.listen((playlist) {
      _currentIndex = playlist.index.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1).toInt();
      notifyListeners();
      unawaited(_syncMediaSession());
    });
    _playingSubscription = player.stream.playing.listen((_) {
      notifyListeners();
      unawaited(_syncMediaSession());
    });
    _completedSubscription = player.stream.completed.listen((_) {
      notifyListeners();
      unawaited(_syncMediaSession());
    });
    _positionSubscription = player.stream.position.listen((_) => unawaited(_syncMediaSession()));
    _durationSubscription = player.stream.duration.listen((_) => unawaited(_syncMediaSession()));
  }

  static final PersistentAudioPlayer instance = PersistentAudioPlayer._();
  static const MethodChannel _mediaChannel = MethodChannel('homeserver/media');

  late final Player player;
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  bool _nativeSessionStarted = false;

  List<MediaQueueItem> _queue = const [];
  ServerApi? _api;
  int _currentIndex = 0;
  bool _active = false;
  bool _music = false;
  bool _fullScreen = false;

  List<MediaQueueItem> get queue => _queue;
  ServerApi? get api => _api;
  int get currentIndex => _currentIndex;
  bool get isActive => _active;
  bool get isMusic => _music;
  bool get isFullScreen => _fullScreen;
  bool get isPlaying => player.state.playing;

  MediaQueueItem? get currentItem =>
      _queue.isEmpty ? null : _queue[_currentIndex.clamp(0, _queue.length - 1).toInt()];

  /// Legacy mini-player widget is intentionally kept hidden; Home uses a FAB.
  bool get showMiniPlayer => false;


  Future<void> openQueue({
    required ServerApi api,
    required List<MediaQueueItem> queue,
    required int initialIndex,
    required bool isMusic,
  }) async {
    if (queue.isEmpty) return;
    _api = api;
    _queue = List.unmodifiable(queue);
    _currentIndex = initialIndex.clamp(0, _queue.length - 1).toInt();
    _music = isMusic;
    _active = true;
    _fullScreen = true;
    notifyListeners();

    final tracks = _queue.map((item) => Media(
      item.localPath ?? api.mediaStreamUrl(item.path, volume: item.volume),
      httpHeaders: item.localPath == null ? api.mediaHeaders : const {},
      extras: {'title': item.title},
    )).toList(growable: false);
    await player.open(Playlist(tracks, index: _currentIndex));
    await _syncMediaSession(start: true);
  }

  void setFullScreen(bool value) {
    _fullScreen = value;
    notifyListeners();
  }

  Future<void> closePlayerScreen({required bool isVideo}) async {
    // Keep the queue and position so HomeScreen can reopen the current session.
    // Pause video when its surface closes; audio continues in the background.
    if (isVideo && player.state.playing) await player.pause();
    _fullScreen = false;
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  Future<void> dismiss() async {
    await player.stop();
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _mediaChannel.invokeMethod<void>('mediaStop');
      } on PlatformException {
        // Keep the player independent from optional Android notification controls.
      } on MissingPluginException {
        // Desktop and test builds do not register the Android media service.
      }
    }
    _nativeSessionStarted = false;
    _active = false;
    _music = false;
    _fullScreen = false;
    _queue = const [];
    _currentIndex = 0;
    _api = null;
    notifyListeners();
  }


  Future<void> _handleMediaCommand(MethodCall call) async {
    if (call.method != 'mediaCommand' || call.arguments is! Map) return;
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    final action = args['action']?.toString();
    switch (action) {
      case 'dev.homeserver.media.PLAY':
        await player.play();
        break;
      case 'dev.homeserver.media.PAUSE':
        await player.pause();
        break;
      case 'dev.homeserver.media.NEXT':
        await player.next();
        break;
      case 'dev.homeserver.media.PREVIOUS':
        await player.previous();
        break;
      case 'dev.homeserver.media.SEEK':
        final position = args['position'];
        if (position is num) await player.seek(Duration(milliseconds: position.toInt()));
        break;
      case 'dev.homeserver.media.STOP':
        await dismiss();
        break;
    }
    await _syncMediaSession();
  }

  Future<void> _syncMediaSession({bool start = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android || !_active || !_music) return;
    final track = currentItem;
    if (track == null) return;
    final args = <String, Object>{
      'title': track.title.replaceAll(RegExp(r'\.[^.]+$'), ''),
      'artist': 'HomeServer music library',
      'playing': player.state.playing,
      'positionMs': player.state.position.inMilliseconds,
      'durationMs': player.state.duration.inMilliseconds,
    };
    try {
      await _mediaChannel.invokeMethod<void>(
        start || !_nativeSessionStarted ? 'mediaStart' : 'mediaUpdate',
        args,
      );
      _nativeSessionStarted = true;
    } on PlatformException {
      // Keep playback independent from optional Android notification controls.
    } on MissingPluginException {
      // Allows Flutter tests and non-Android targets to run without the plugin.
    }
  }

  @override
  void dispose() {
    unawaited(_playlistSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    _mediaChannel.setMethodCallHandler(null);
    unawaited(player.dispose());
    super.dispose();
  }
}
