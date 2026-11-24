import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/home_activity_store.dart';

class MediaQueueItem {
  const MediaQueueItem({required this.title, required this.path, this.volume, this.localPath, this.size, this.streamUrl, this.httpHeaders = const {}, this.artist, this.artworkUrl, this.lyricsVideoId, this.durationText = '', this.streamCodec, this.streamResolver, this.streamBitrateBps});

  final String title;
  final String path;
  final String? volume;
  final String? localPath;
  final int? size;
  final String? streamUrl;
  final Map<String, String> httpHeaders;
  final String? artist;
  final String? artworkUrl;
  final String? lyricsVideoId;
  final String durationText;
  final String? streamCodec;
  final String? streamResolver;
  final int? streamBitrateBps;

  /// Stable identity for artwork, lyrics, and track-scoped UI state.
  /// Mutable playback state is deliberately excluded.
  String get stableTrackId {
    final normalizedPath = path.trim().toLowerCase();
    if (normalizedPath.isNotEmpty) {
      return 'file:' + (volume ?? 'internal').trim().toLowerCase() + ':' + normalizedPath;
    }
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) return 'local:' + local;
    final videoId = lyricsVideoId?.trim();
    if (videoId != null && videoId.isNotEmpty) return 'discover:' + videoId;
    String normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'metadata:' + normalize(title) + '|' + normalize(artist ?? '');
  }

  /// Merge refreshed metadata without discarding known artwork or lyrics IDs.
  MediaQueueItem mergeMetadata(MediaQueueItem update) => MediaQueueItem(
        title: update.title.trim().isEmpty ? title : update.title,
        path: update.path.trim().isEmpty ? path : update.path,
        volume: update.volume ?? volume,
        localPath: update.localPath ?? localPath,
        size: update.size ?? size,
        streamUrl: update.streamUrl ?? streamUrl,
        httpHeaders: update.httpHeaders.isEmpty ? httpHeaders : update.httpHeaders,
        artist: update.artist ?? artist,
        artworkUrl: (update.artworkUrl?.trim().isNotEmpty ?? false) ? update.artworkUrl : artworkUrl,
        lyricsVideoId: update.lyricsVideoId ?? lyricsVideoId,
        durationText: update.durationText.isEmpty ? durationText : update.durationText,
        streamCodec: update.streamCodec ?? streamCodec,
        streamResolver: update.streamResolver ?? streamResolver,
        streamBitrateBps: update.streamBitrateBps ?? streamBitrateBps,
      );

  /// Describes the origin of the media, not the device or cache used to play it.
  String get sourceLabel {
    if (localPath != null) return 'Local';
    if (streamUrl != null) return 'Discover';
    return 'PocketLink';
  }
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
      if (current != null && current.localPath == null && current.streamUrl == null && _active && _music && _api != null) {
        unawaited(HomeActivityStore.instance.recordTrack(serverUrl: _api!.baseUrl, title: current.title, path: current.path, volume: current.volume));
      }
      notifyListeners();
      unawaited(_syncMediaSession());
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      AppLogger.event(playing ? 'playback.started' : 'playback.paused',
        category: 'media', component: 'persistent_player',
        fields: {'queue_length': _queue.length, 'queue_index': _currentIndex,
          'source': currentItem?.sourceLabel ?? 'unknown'});
      if (playing) _miniPlayerDismissed = false;
      notifyListeners();
      unawaited(_syncMediaSession());
    });
    _completedSubscription = player.stream.completed.listen((_) {
      AppLogger.event('playback.completed', category: 'media',
        component: 'persistent_player',
        fields: {'queue_length': _queue.length, 'queue_index': _currentIndex});
      notifyListeners();
      unawaited(_syncMediaSession());
    });
    _errorSubscription = player.stream.error.listen((message) {
      AppLogger.warning('Playback engine reported an error', category: 'media',
        component: 'persistent_player',
        fields: {'error_present': message.isNotEmpty, 'queue_index': _currentIndex});
      unawaited(_handlePlaybackError(message));
    });
    // Do not publish every decoder position/duration tick over the platform
    // channel. Android's media session extrapolates position from playback
    // state; syncing on track and play-state changes is sufficient.
  }

  static final PersistentAudioPlayer instance = PersistentAudioPlayer._();
  static const MethodChannel _mediaChannel = MethodChannel('pocketlink/media');
  static const MethodChannel _discoverChannel = MethodChannel('pocketlink/saf');

  late final Player player;
  VideoController? _videoController;

  /// Reuse one video output for the lifetime of the app-scoped Player.
  /// media_kit_video releases its controller when the Player is disposed.
  VideoController get videoController =>
      _videoController ??= VideoController(player);
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _nativeSessionStarted = false;
  Timer? _sleepTimer;

  List<MediaQueueItem> _queue = const [];
  ServerApi? _api;
  int _currentIndex = 0;
  bool _active = false;
  bool _music = false;
  bool _selectionLoading = false;
  bool _miniPlayerDismissed = false;
  int? _pendingTrackDirection;
  DateTime? _pendingTrackDirectionAt;
  int _queueSession = 0;
  Future<void> _queueMutationTail = Future<void>.value();
  final Set<String> _retriedDiscoverTracks = <String>{};
  bool _retryingDiscoverPlayback = false;

  List<MediaQueueItem> get queue => _queue;
  int get queueSession => _queueSession;

  Future<void> _serializeQueueMutation(Future<void> Function() operation) {
    final pending = _queueMutationTail.then((_) => operation());
    _queueMutationTail = pending.catchError((Object _) {});
    return pending;
  }
  ServerApi? get api => _api;
  int get currentIndex => _currentIndex;
  bool get isActive => _active;
  bool get isMusic => _music;
  bool get isSelectionLoading => _selectionLoading;

  /// Publishes track metadata immediately while its playable source resolves.
  /// The returned session invalidates any older in-flight selection.
  int beginQueueSelection({
    required ServerApi? api,
    required MediaQueueItem item,
    required bool isMusic,
  }) {
    final session = ++_queueSession;
    _api = api;
    _queue = List.unmodifiable([item]);
    _currentIndex = 0;
    _music = isMusic;
    _active = true;
    _miniPlayerDismissed = false;
    _selectionLoading = true;
    _retriedDiscoverTracks.clear();
    _retryingDiscoverPlayback = false;
    notifyListeners();
    unawaited(player.pause());
    return session;
  }

  void failQueueSelection(int session) {
    if (session != _queueSession || !_selectionLoading) return;
    _selectionLoading = false;
    notifyListeners();
  }
  bool get isMiniPlayerDismissed => _miniPlayerDismissed;
  bool get shouldShowMiniPlayer =>
      _music && _active && currentItem != null && !_miniPlayerDismissed;
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

  /// Legacy widget compatibility; the app-level overlay owns the live bar.
  bool get showMiniPlayer => false;

  Future<void> openQueue({
    ServerApi? api,
    required List<MediaQueueItem> queue,
    required int initialIndex,
    required bool isMusic,
    int? expectedSession,
  }) async {
    if (queue.isEmpty) return;
    final session = expectedSession ?? ++_queueSession;
    if (session != _queueSession) return;
    if (api == null && queue.any((item) => item.streamUrl == null && item.localPath == null)) {
      throw StateError('A server connection is required for server-hosted media.');
    }
    _api = api;
    _queue = List.unmodifiable(queue);
    _retriedDiscoverTracks.clear();
    _retryingDiscoverPlayback = false;
    _currentIndex = initialIndex.clamp(0, _queue.length - 1).toInt();
    _music = isMusic;
    _active = true;
    _miniPlayerDismissed = false;
    _selectionLoading = true;
    notifyListeners();

    final tracks = _queue.map((item) => Media(
      item.localPath ?? item.streamUrl ?? api!.mediaStreamUrl(item.path, volume: item.volume),
      httpHeaders: item.localPath != null
          ? const {}
          : item.streamUrl != null
              ? item.httpHeaders
              : api!.mediaHeaders,
      extras: {'title': item.title, if (item.artist != null) 'artist': item.artist},
    )).toList(growable: false);
    try {
      await _serializeQueueMutation(() async {
        if (session != _queueSession) return;
        await player.open(Playlist(tracks, index: _currentIndex));
      });
    } catch (_) {
      if (session == _queueSession) {
        _selectionLoading = false;
        notifyListeners();
      }
      rethrow;
    }
    if (session != _queueSession) return;
    _selectionLoading = false;
    notifyListeners();
    final current = currentItem;
    if (current != null && current.localPath == null && current.streamUrl == null && _music && api != null) {
      unawaited(HomeActivityStore.instance.recordTrack(serverUrl: api.baseUrl, title: current.title, path: current.path, volume: current.volume));
    }
    await _syncMediaSession(start: true);
  }

  Future<void> _handlePlaybackError(String message) async {
    final item = currentItem;
    if (item == null) return;
    // Stop the playlist's automatic advance while a failed Discover stream is retried.
    if (item.streamUrl != null && item.lyricsVideoId != null) {
      await player.pause();
    }
    await AppLogger.error(
      'Native media playback failed',
      category: 'media',
      component: 'audio_player',
      error: message,
      fields: {
        'source': item.sourceLabel,
        'title': item.title,
        'codec': item.streamCodec ?? 'unknown',
        'resolver': item.streamResolver ?? 'unknown',
        'bitrate_bps': item.streamBitrateBps ?? 0,
        'queue_index': _currentIndex,
        'queue_length': _queue.length,
      },
    );
    if (item.streamUrl == null || item.lyricsVideoId == null ||
        _retryingDiscoverPlayback) return;

    final retryKey = '$_queueSession:${item.lyricsVideoId}';
    if (!_retriedDiscoverTracks.add(retryKey)) return;
    _retryingDiscoverPlayback = true;
    final session = _queueSession;
    try {
      final currentResolver = (item.streamResolver ?? '').toLowerCase();
      final alternateProfile = currentResolver.startsWith('newpipe')
          ? 'player_api_first'
          : 'newpipe_first';
      final settings = AppSettings.instance;
      final resolved = await _discoverChannel.invokeMapMethod<String, dynamic>(
        'discoverResolve',
        {
          'videoId': item.lyricsVideoId,
          'quality': settings.discoverAudioQuality,
          'resolverProfile': alternateProfile,
          'region': settings.discoverRegion,
        },
      );
      if (session != _queueSession) return;
      if (resolved == null || (resolved['url']?.toString().isEmpty ?? true)) {
        await AppLogger.warning(
          'Discover alternate resolver returned no playable stream',
          category: 'media',
          component: 'discover_resolver',
          fields: {'queue_index': _currentIndex},
        );
        return;
      }

      final retryItem = MediaQueueItem(
        title: item.title,
        path: item.path,
        volume: item.volume,
        localPath: item.localPath,
        size: item.size,
        streamUrl: resolved['url']?.toString(),
        artist: item.artist,
        artworkUrl: item.artworkUrl,
        lyricsVideoId: item.lyricsVideoId,
        durationText: item.durationText,
        streamCodec: resolved['codec']?.toString(),
        streamResolver: resolved['resolver']?.toString(),
        streamBitrateBps: (resolved['bitrateBps'] as num?)?.toInt(),
        httpHeaders: {
          'User-Agent': resolved['userAgent']?.toString() ?? '',
          'Accept': '*/*',
        },
      );
      var retryIndex = -1;
      await _serializeQueueMutation(() async {
        if (session != _queueSession) return;
        final updated = _queue.toList();
        retryIndex = updated.indexWhere(
          (queued) => queued.lyricsVideoId == item.lyricsVideoId &&
              queued.streamUrl == item.streamUrl,
        );
        if (retryIndex < 0 || session != _queueSession) return;
        updated[retryIndex] = updated[retryIndex].mergeMetadata(retryItem);
        _queue = List.unmodifiable(updated);
        _currentIndex = retryIndex;
        final api = _api;
        final media = _queue.map((queued) => Media(
          queued.localPath ?? queued.streamUrl ??
              api!.mediaStreamUrl(queued.path, volume: queued.volume),
          httpHeaders: queued.localPath != null
              ? const {}
              : queued.streamUrl != null
                  ? queued.httpHeaders
                  : api!.mediaHeaders,
          extras: {
            'title': queued.title,
            if (queued.artist != null) 'artist': queued.artist,
          },
        )).toList(growable: false);
        await player.open(Playlist(media, index: retryIndex));
      });
      if (session != _queueSession) return;
      if (retryIndex < 0) {
        await AppLogger.warning(
          'Discover retry discarded because the failed queue item changed',
          category: 'media',
          component: 'discover_resolver',
          fields: {'queue_index': _currentIndex},
        );
        return;
      }
      await AppLogger.info(
        'Discover playback retried with alternate resolver',
        category: 'media',
        component: 'discover_resolver',
        fields: {
          'resolver': retryItem.streamResolver ?? 'unknown',
          'codec': retryItem.streamCodec ?? 'unknown',
          'bitrate_bps': retryItem.streamBitrateBps ?? 0,
          'queue_index': retryIndex,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.error(
        'Discover alternate resolver retry failed',
        category: 'media',
        component: 'discover_resolver',
        error: error,
        stackTrace: stackTrace,
        fields: {'queue_index': _currentIndex},
      );
    } finally {
      _retryingDiscoverPlayback = false;
    }
  }

  /// Adds an original server/local media item to the active queue.
  Future<void> enqueue(
    MediaQueueItem item, {
    bool playNext = false,
    bool insertAtStart = false,
    int? expectedSession,
  }) async {
    final requestedSession = expectedSession ?? _queueSession;
    await _serializeQueueMutation(() async {
      if (!_active || requestedSession != _queueSession ||
          (item.localPath == null && item.streamUrl == null && _api == null)) {
        return;
      }
      final api = _api;
      final session = requestedSession;
      final media = Media(
        item.localPath ?? item.streamUrl ?? api!.mediaStreamUrl(item.path, volume: item.volume),
        httpHeaders: item.localPath != null
            ? const {}
            : item.streamUrl != null
                ? item.httpHeaders
                : api!.mediaHeaders,
        extras: {'title': item.title, if (item.artist != null) 'artist': item.artist},
      );
      final oldLength = _queue.length;
      await player.add(media);
      if (session != _queueSession) return;
      final updated = _queue.toList();
      if (insertAtStart && oldLength > 0) {
        await player.move(oldLength, 0);
        updated.insert(0, item);
        _currentIndex = (_currentIndex + 1).clamp(0, updated.length - 1).toInt();
      } else if (playNext && oldLength > 0) {
        final target = (_currentIndex + 1).clamp(0, oldLength).toInt();
        if (target < oldLength) await player.move(oldLength, target);
        updated.insert(target, item);
      } else {
        updated.add(item);
      }
      _queue = List.unmodifiable(updated);
      notifyListeners();
    });
  }

  void dismissMiniPlayer() {
    if (player.state.playing || _miniPlayerDismissed) return;
    _miniPlayerDismissed = true;
    notifyListeners();
  }

  Future<void> closePlayerScreen({required bool isVideo}) async {
    // Keep the queue and position when a player surface closes.
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

  void _recordTrackChangeDirection(int direction) {
    _pendingTrackDirection = direction;
    _pendingTrackDirectionAt = DateTime.now();
  }

  /// Returns the direction of a recent explicit skip request, if any.
  /// Used by the UI's track-change animation; it does not affect playback.
  int? takePendingTrackDirection() {
    final direction = _pendingTrackDirection;
    final requestedAt = _pendingTrackDirectionAt;
    _pendingTrackDirection = null;
    _pendingTrackDirectionAt = null;
    if (requestedAt == null ||
        DateTime.now().difference(requestedAt) > const Duration(seconds: 2)) {
      return null;
    }
    return direction;
  }

  Future<void> skipToNext() async {
    _recordTrackChangeDirection(1);
    await player.next();
  }

  Future<void> skipToPrevious() async {
    _recordTrackChangeDirection(-1);
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
    _miniPlayerDismissed = false;
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
        await skipToNext();
        break;
      case 'io.github.augztn.pocketlink.media.PREVIOUS':
        await skipToPrevious();
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
      'artist': track.artist ?? 'PocketLink music library',
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
    unawaited(_errorSubscription?.cancel());
    _mediaChannel.setMethodCallHandler(null);
    unawaited(player.dispose());
    super.dispose();
  }
}
