import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/network/server_api.dart';
import '../../core/storage/home_activity_store.dart';

class MediaQueueItem {
  const MediaQueueItem({required this.title, required this.path, this.volume, this.localPath, this.size});

  final String title;
  final String path;
  final String? volume;
  final String? localPath;
  final int? size;
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
      final current = currentItem;
      if (current != null && current.localPath == null && _active && _music && _api != null) {
        unawaited(HomeActivityStore.instance.recordTrack(serverUrl: _api!.baseUrl, title: current.title, path: current.path, volume: current.volume));
      }
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
    // Do not publish every decoder position/duration tick over the platform
    // channel. Android's media session extrapolates position from playback
    // state; syncing on track and play-state changes is sufficient.
  }

  static final PersistentAudioPlayer instance = PersistentAudioPlayer._();
  static const MethodChannel _mediaChannel = MethodChannel('pocketlink/media');

  late final Player player;
  VideoController? _videoController;

  /// Reuse one video output for the lifetime of the app-scoped Player.
  /// media_kit_video releases its controller when the Player is disposed.
  VideoController get videoController =>
      _videoController ??= VideoController(player);
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  bool _nativeSessionStarted = false;
  Timer? _sleepTimer;

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
  bool get hasSleepTimer => _sleepTimer?.isActive ?? false;

  /// Pauses playback after [duration], even if the Now Playing screen is closed.
  void schedulePauseAfter(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      unawaited(player.pause());
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  MediaQueueItem? get currentItem =>
      _queue.isEmpty ? null : _queue[_currentIndex.clamp(0, _queue.length - 1).toInt()];

  /// The app-wide mini player is available for active background music only.
  bool get showMiniPlayer => _active && _music && !_fullScreen && currentItem != null;


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
    final current = currentItem;
    if (current != null && current.localPath == null && _music) {
      unawaited(HomeActivityStore.instance.recordTrack(serverUrl: api.baseUrl, title: current.title, path: current.path, volume: current.volume));
    }
    await _syncMediaSession(start: true);
  }

  /// Adds an original server/local media item to the active queue.
  Future<void> enqueue(MediaQueueItem item, {bool playNext = false}) async {
    if (!_active || _api == null) return;
    final media = Media(
      item.localPath ?? _api!.mediaStreamUrl(item.path, volume: item.volume),
      httpHeaders: item.localPath == null ? _api!.mediaHeaders : const {},
      extras: {'title': item.title},
    );
    final oldLength = _queue.length;
    await player.add(media);
    final updated = _queue.toList();
    if (playNext && oldLength > 0) {
      final target = (_currentIndex + 1).clamp(0, oldLength).toInt();
      if (target < oldLength) await player.move(oldLength, target);
      updated.insert(target, item);
    } else {
      updated.add(item);
    }
    _queue = List.unmodifiable(updated);
    notifyListeners();
  }

  void setFullScreen(bool value) {
    _fullScreen = value;
    notifyListeners();
  }

  Future<void> closePlayerScreen({required bool isVideo}) async {
    // Release the full-screen UI state before awaiting media operations. A new
    // player screen may open while a video pause is still completing.
    _fullScreen = false;
    notifyListeners();

    // Keep the queue and position so HomeScreen can reopen the current session.
    // Pause video when its surface closes; audio continues in the background.
    if (isVideo && player.state.playing) await player.pause();
  }

  Future<void> togglePlayback() async {
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  Future<void> skipToNext() async {
    await player.next();
  }

  Future<void> skipToPrevious() async {
    await player.previous();
  }

  Future<void> dismiss() async {
    cancelSleepTimer();
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
      case 'io.github.augztn.pocketlink.media.PLAY':
        await player.play();
        break;
      case 'io.github.augztn.pocketlink.media.PAUSE':
        await player.pause();
        break;
      case 'io.github.augztn.pocketlink.media.NEXT':
        await player.next();
        break;
      case 'io.github.augztn.pocketlink.media.PREVIOUS':
        await player.previous();
        break;
      case 'io.github.augztn.pocketlink.media.SEEK':
        final position = args['position'];
        if (position is num) await player.seek(Duration(milliseconds: position.toInt()));
        break;
      case 'io.github.augztn.pocketlink.media.STOP':
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
      'artist': 'PocketLink music library',
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
    cancelSleepTimer();
    unawaited(_playlistSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    _mediaChannel.setMethodCallHandler(null);
    unawaited(player.dispose());
    super.dispose();
  }
}
