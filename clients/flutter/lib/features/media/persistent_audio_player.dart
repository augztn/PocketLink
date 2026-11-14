import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/network/server_api.dart';

class MediaQueueItem {
  const MediaQueueItem({required this.title, required this.path, this.volume});

  final String title;
  final String path;
  final String? volume;
}

/// App-scoped owner for the native media engine.
///
/// Screens may come and go; the Player remains alive until the app process ends.
class PersistentAudioPlayer extends ChangeNotifier {
  PersistentAudioPlayer._() {
    player = Player();
    _playlistSubscription = player.stream.playlist.listen((playlist) {
      _currentIndex = playlist.index.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
      notifyListeners();
    });
    _playingSubscription = player.stream.playing.listen((_) => notifyListeners());
    _completedSubscription = player.stream.completed.listen((_) => notifyListeners());
  }

  static final PersistentAudioPlayer instance = PersistentAudioPlayer._();

  late final Player player;
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;

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
      _queue.isEmpty ? null : _queue[_currentIndex.clamp(0, _queue.length - 1)];

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
    _currentIndex = initialIndex.clamp(0, _queue.length - 1);
    _music = isMusic;
    _active = true;
    _fullScreen = true;
    notifyListeners();

    final tracks = _queue.map((item) => Media(
      api.mediaStreamUrl(item.path, volume: item.volume),
      httpHeaders: api.mediaHeaders,
      extras: {'title': item.title},
    )).toList(growable: false);
    await player.open(Playlist(tracks, index: _currentIndex));
  }

  void setFullScreen(bool value) {
    _fullScreen = value;
    notifyListeners();
  }

  Future<void> closePlayerScreen({required bool isVideo}) async {
    _fullScreen = false;
    if (isVideo) {
      await dismiss();
    } else {
      notifyListeners();
    }
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
    _active = false;
    _music = false;
    _fullScreen = false;
    _queue = const [];
    _currentIndex = 0;
    _api = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_playlistSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(player.dispose());
    super.dispose();
  }
}
