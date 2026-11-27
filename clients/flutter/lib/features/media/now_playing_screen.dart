import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/offline_file_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';
import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../storage/storage_browser_screen.dart';
import 'track_artwork_view.dart';
import 'now_playing_lyrics_mode.dart';
import 'now_playing_scrubber.dart';
import 'now_playing_transport_controls.dart';
import 'now_playing_scroll_dismiss_detector.dart';
import 'persistent_audio_player.dart';
import 'now_playing_artwork_palette.dart';
import 'discover/discover_thumbnail_cache.dart';
import 'widgets/media_info_row.dart';
import 'track_options_sheet.dart';
import '../downloads/download_manager_service.dart';
import 'lyrics/lyrics_repository.dart';
import 'media_metadata.dart';
import 'lyrics/lyrics_viewport.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({
    this.api,
    required this.queue,
    this.initialIndex = 0,
    this.resumeExisting = false,
    this.morphAnimation,
    this.useSharedArtwork = false,
    this.artworkTargetKey,
    this.onArtworkChanged,
    required this.onDismiss,
    required this.onDismissDragStart,
    required this.onDismissDragUpdate,
    required this.onDismissDragEnd,
    super.key,
  });

  final ServerApi? api;
  final VoidCallback onDismiss;
  final VoidCallback onDismissDragStart;
  final ValueChanged<double> onDismissDragUpdate;
  final ValueChanged<double> onDismissDragEnd;
  final List<MediaQueueItem> queue;
  final int initialIndex;
  final bool resumeExisting;
  final Animation<double>? morphAnimation;
  final bool useSharedArtwork;
  final GlobalKey? artworkTargetKey;
  final ValueChanged<Uint8List?>? onArtworkChanged;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> with SingleTickerProviderStateMixin {
  static const _secureStorage = FlutterSecureStorage();
  static const double _playerChromeHeight = 260;

  late final PersistentAudioPlayer _persistent;
  late final Player _player;
  StreamSubscription<Playlist>? _playlistSubscription;
  Uint8List? _artwork;
  String? _artworkKey;
  List<Color>? _artworkPalette;
  int _artworkRequest = 0;
  bool _cached = false;
  Set<String> _favorites = <String>{};
  double _trackSwipeDistance = 0;
  late final AnimationController _lyricsController;
  final LyricsRepository _lyricsRepository = LyricsRepository();
  Map<String, LyricsProviderResult> _lyricsProviderStates = const {};
  LyricsDocument? _activeLyrics;
  String? _lyricsQueryKey;
  bool _lyricsLoading = false;
  bool _lyricsTranslationEnabled = false;
  String? _observedTrackIdentity;
  final GlobalKey _lyricsViewportKey = GlobalKey();


  MediaQueueItem get _track =>
      _persistent.currentItem ??
      widget.queue[widget.initialIndex.clamp(0, widget.queue.length - 1).toInt()];

  String get _trackIdentity =>
      '${widget.api?.baseUrl ?? 'discover'}|${_track.stableTrackId}';

  String get _trackKey => _trackIdentity;


  String get _favoriteId => '${_track.volume ?? 'internal'}:${_track.path}';

  String get _favoriteStorageKey =>
      'pocketlink.music.favorites.${Uri.encodeComponent(widget.api?.baseUrl ?? 'discover')}';

  String get _legacyFavoriteStorageKey =>
      'homeserver.music.favorites.${Uri.encodeComponent(widget.api?.baseUrl ?? 'discover')}';

  bool get _isFavorite => _favorites.contains(_favoriteId);

  String get _outputDeviceLabel {
    final host = Platform.localHostname.trim();
    return host.isEmpty || host.toLowerCase() == 'localhost' ? 'This device' : host;
  }

  String get _fileName {
    final pathName = _track.path.split('/').last;
    final raw = _track.title.trim().isNotEmpty ? _track.title : pathName;
    final dot = raw.lastIndexOf('.');
    final name = (dot > 0 ? raw.substring(0, dot) : raw)
        .replaceAll('_', ' ')
        .trim();
    final artist = _folderName.trim();
    final suffixStart = name.lastIndexOf(' - ');
    if (suffixStart >= 0 &&
        artist.isNotEmpty &&
        name.substring(suffixStart + 3).trim().toLowerCase() ==
            artist.toLowerCase()) {
      return name.substring(0, suffixStart).trim();
    }
    return name;
  }

  String get _folder {
    final separator = _track.path.lastIndexOf('/');
    return separator < 0 ? '' : _track.path.substring(0, separator);
  }

  String get _folderName {
    if (_folder.isNotEmpty) return _folder.split('/').last;
    return _track.volume == null ? 'Internal storage' : 'External storage';
  }

  String get _formatTag {
    final name = _track.path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'AUDIO';
    return name.substring(dot + 1).toUpperCase();
  }

  List<Color> get _trackPalette => _artworkPalette ??
      NowPlayingArtworkPalette.fallback(
        title: _track.title,
        folderName: _folderName,
        path: _track.path,
      );

  Widget _ambientBackground() {
    final palette = _trackPalette;
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette[0], const Color(0xFFB65D38), 0.22)!,
            Color.lerp(palette[1], const Color(0xFF6D3427), 0.32)!,
            Color.lerp(palette[2], const Color(0xFF160D0B), 0.38)!,
            const Color(0xFF050505),
          ],
          stops: const [0, 0.34, 0.70, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArtwork)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: Opacity(
                opacity: 0.48,
                child: Image.memory(_artwork!, cacheWidth: 720, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x26000000), Color(0xB8000000), Color(0xF5000000)],
                stops: [0, 0.40, 0.78, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _lyricsController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350), reverseDuration: const Duration(milliseconds: 350));
    unawaited(_loadLyricsPreference());
    _persistent = PersistentAudioPlayer.instance;
    _player = _persistent.player;
    _observedTrackIdentity = _trackIdentity;
    unawaited(AppLogger.info('Now Playing screen initialized', fields: {
      'queueLength': widget.queue.length,
      'initialIndex': widget.initialIndex,
      'resumeExisting': widget.resumeExisting,
    }));
    _playlistSubscription = _player.stream.playlist.listen((_) => _onTrackChanged());
    unawaited(_initialize());
    if (!widget.resumeExisting) unawaited(_openQueue());
  }

  Future<void> _openQueue() async {
    try {
      await _persistent.openQueue(
        api: widget.api,
        queue: widget.queue,
        initialIndex: widget.initialIndex,
        isMusic: true,
      );
      await AppLogger.info('Now Playing queue opened', fields: {
        'queueLength': widget.queue.length,
      });
    } catch (error, stackTrace) {
      await AppLogger.error(
        'Now Playing queue failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _message('Could not start playback. Check diagnostics for details.');
    }
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadFavorites(),
      _refreshCacheStatus(),
      _loadArtwork(),
    ]);
  }

  Future<void> _loadFavorites() async {
    try {
      var raw = await _secureStorage.read(key: _favoriteStorageKey);
      if (raw == null) {
        raw = await _secureStorage.read(key: _legacyFavoriteStorageKey);
        if (raw != null) {
          await _secureStorage.write(key: _favoriteStorageKey, value: raw);
        }
      }
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final favorites = decoded.whereType<String>().toSet();
        if (mounted) setState(() => _favorites = favorites);
      }
    } catch (_) {
      // A corrupt local favorites index must not prevent playback.
    }
  }

  Future<void> _toggleFavorite() async {
    final updated = Set<String>.from(_favorites);
    if (!updated.add(_favoriteId)) updated.remove(_favoriteId);
    try {
      await _secureStorage.write(
        key: _favoriteStorageKey,
        value: jsonEncode(updated.toList()),
      );
      if (mounted) setState(() => _favorites = updated);
    } catch (_) {
      _message('Could not save this favorite on the device.');
    }
  }

  Future<void> _refreshCacheStatus() async {
    final api = widget.api;
    if (api == null || _track.streamUrl != null || _track.localPath != null) {
      if (mounted) setState(() => _cached = false);
      return;
    }
    final cached = await OfflineFileCache().find(
      OfflineFileCache().serverId(api),
      _track.volume,
      _track.path,
    );
    if (mounted) setState(() => _cached = cached != null);
  }

  Future<void> _onTrackChanged() async {
    if (!mounted) return;
    final identity = _trackIdentity;
    if (identity == _observedTrackIdentity) {
      // Playlist snapshots can be emitted for decoder/metadata changes.
      // Preserve artwork, palette, and lyrics while the same song is active.
      if (_artwork == null && (_track.artworkUrl?.trim().isNotEmpty ?? false)) {
        unawaited(_loadArtwork());
      }
      return;
    }

    _observedTrackIdentity = identity;
    final previousLyricsKey = _lyricsQueryKey;
    if (previousLyricsKey != null) _lyricsRepository.cancel(previousLyricsKey);
    setState(() {
      _artwork = null;
      _artworkKey = null;
      _artworkPalette = null;
      _lyricsQueryKey = null;
      _activeLyrics = null;
      _lyricsProviderStates = const {};
      _lyricsLoading = false;
    });
    widget.onArtworkChanged?.call(null);
    await Future.wait([
      _refreshCacheStatus(),
      _loadArtwork(),
    ]);
    if (_lyricsController.status == AnimationStatus.forward ||
        _lyricsController.status == AnimationStatus.completed) {
      await _loadTrackLyrics();
    }
  }

  Future<void> _loadArtwork() async {
    final request = ++_artworkRequest;
    final key = _trackKey;
    if (_track.localPath == null && (_track.artworkUrl?.isNotEmpty ?? false)) {
      try {
        final bytes = await DiscoverThumbnailCache.load(
          DiscoverThumbnailCache.urlForSize(_track.artworkUrl!, 544),
        );
        if (!mounted || request != _artworkRequest) return;
        if (bytes != null && bytes.isNotEmpty) {
          final palette = await NowPlayingArtworkPalette.extract(bytes);
          if (!mounted || request != _artworkRequest) return;
          setState(() {
            _artwork = bytes;
            _artworkKey = key;
            _artworkPalette = palette;
          });
          widget.onArtworkChanged?.call(bytes);
          return;
        }
      } catch (_) {
        // Continue to server folder artwork when a remote thumbnail is unavailable.
      }
    }

    if (_track.localPath != null || _folder.isEmpty) {
      if (mounted) {
        setState(() {
          _artwork = null;
          _artworkKey = key;
          _artworkPalette = null;
        });
      }
      widget.onArtworkChanged?.call(null);
      return;
    }

    // PocketLink currently exposes raw files, not embedded-artwork metadata.
    // Use an existing folder cover file when present; otherwise show the
    // compact artwork fallback rather than a blank full-height region.
    final api = widget.api;
    if (api == null) {
      if (mounted && request == _artworkRequest) {
        setState(() {
          _artwork = null;
          _artworkKey = key;
          _artworkPalette = null;
        });
      }
      widget.onArtworkChanged?.call(null);
      return;
    }
    try {
      final listing = _track.volume == null
          ? await api.listDirectory(_folder)
          : await api.listStorageDirectory(_track.volume!, _folder);
      const candidates = {
        'cover.jpg', 'cover.jpeg', 'cover.png', 'cover.webp',
        'folder.jpg', 'folder.png', 'album.jpg', 'album.png', 'front.jpg',
      };
      FileEntry? cover;
      for (final item in listing.items) {
        if (!item.isDirectory && candidates.contains(item.name.toLowerCase())) {
          cover = item;
          break;
        }
      }
      if (cover != null) {
        final path = '$_folder/${cover.name}';
        final bytes = _track.volume == null
            ? await api.downloadFile(path)
            : await api.downloadStorageFile(_track.volume!, path);
        if (!mounted || request != _artworkRequest) return;
        if (bytes.isNotEmpty) {
          final palette = await NowPlayingArtworkPalette.extract(bytes);
          if (!mounted || request != _artworkRequest) return;
          setState(() {
            _artwork = bytes;
            _artworkKey = key;
            _artworkPalette = palette;
          });
          widget.onArtworkChanged?.call(bytes);
          return;
        }
      }
    } catch (_) {
      // Artwork is optional; playback must not depend on it.
    }
    if (mounted && request == _artworkRequest) {
      setState(() {
        _artwork = null;
        _artworkKey = key;
        _artworkPalette = null;
      });
      widget.onArtworkChanged?.call(null);
    }
  }

  Future<void> _runOption(TrackOptionAction action) async {
    switch (action) {
      case TrackOptionAction.favorite:
        await _toggleFavorite();
        break;
      case TrackOptionAction.download:
        await _downloadTrack();
        break;
      case TrackOptionAction.share:
        await _shareTrack();
        break;
      case TrackOptionAction.playNext:
        await _persistent.enqueue(_track, playNext: true);
        _message('Queued to play next.');
        break;
      case TrackOptionAction.addToQueue:
        await _persistent.enqueue(_track);
        _message('Added to queue.');
        break;
      case TrackOptionAction.showInFolder:
        _showInFolder();
        break;
      case TrackOptionAction.fileInfo:
        _showFileInfo();
        break;
      case TrackOptionAction.sleepTimer:
        await _chooseSleepTimer();
        break;
      case TrackOptionAction.removeFromCache:
        final api = widget.api;
        if (api == null) break;
        await OfflineFileCache().remove(
          OfflineFileCache().serverId(api),
          _track.volume,
          _track.path,
        );
        if (mounted) setState(() => _cached = false);
        _message('Removed from offline cache.');
        break;
    }
  }

  Future<Uint8List> _fileBytes() async {
    if (_track.localPath != null) {
      return File(_track.localPath!).readAsBytes();
    }
    final api = widget.api;
    if (api == null) throw StateError('This Discover stream is not a server file.');
    final bytes = _track.volume == null
        ? await api.downloadFile(_track.path)
        : await api.downloadStorageFile(_track.volume!, _track.path);
    if (bytes.isEmpty) throw StateError('The server returned an empty file.');
    return bytes;
  }

  Future<void> _downloadTrack() async {
    if (_track.localPath != null) {
      _message('This track is already stored on this device.');
      return;
    }
    final api = widget.api;
    if (api == null) {
      _message('Downloads are unavailable for Discover streams.');
      return;
    }
    try {
      await DownloadManagerService.instance.enqueueServerFile(
        api: api,
        name: _track.path.split('/').last,
        sourcePath: _track.path,
        volume: _track.volume,
        size: _track.size,
      );
      _message('Added to Downloads.');
    } catch (_) {
      _message('Could not add this track to Downloads.');
    }
  }

  Future<void> _shareTrack() async {
    try {
      final bytes = await _fileBytes();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: _track.path.split('/').last)],
          text: _fileName,
        ),
      );
    } catch (_) {
      _message('Could not share this track.');
    }
  }

  Future<int?> _resolveFileSize() async {
    if (_track.size != null) return _track.size;
    if (_track.localPath != null) {
      try {
        return await File(_track.localPath!).length();
      } catch (_) {
        return null;
      }
    }
    final api = widget.api;
    if (api == null) return null;
    try {
      final listing = _track.volume == null
          ? await api.listDirectory(_folder)
          : await api.listStorageDirectory(_track.volume!, _folder);
      final name = _track.path.split('/').last;
      for (final entry in listing.items) {
        if (!entry.isDirectory && entry.name == name) return entry.size;
      }
    } catch (_) {
      // File information remains useful even when the parent folder is offline.
    }
    return null;
  }

  void _showFileInfo() {
    final fileName = _track.path.split('/').last;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => FutureBuilder<int?>(
        future: _resolveFileSize(),
        builder: (context, snapshot) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('File info', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaInfoRow('Filename', fileName),
              MediaInfoRow('Format', _formatTag),
              MediaInfoRow(
                'Size',
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Reading…'
                    : snapshot.data == null
                        ? 'Unavailable'
                        : _formatBytes(snapshot.data!),
              ),
              MediaInfoRow('Server path', _track.path),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseSleepTimer() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Sleep timer', style: TextStyle(color: Colors.white)),
            ),
            for (final value in [15, 30, 45, 60, 90])
              ListTile(
                title: Text('$value minutes', style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, value),
              ),
            if (_persistent.hasSleepTimer)
              ListTile(
                title: const Text('Cancel timer', style: TextStyle(color: Colors.white70)),
                onTap: () => Navigator.pop(context, 0),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    if (minutes == 0) {
      _persistent.cancelSleepTimer();
      _message('Sleep timer cancelled.');
      return;
    }
    _persistent.schedulePauseAfter(Duration(minutes: minutes));
    _message('Playback will pause in $minutes minutes.');
  }

  void _showInFolder() {
    final api = widget.api;
    if (api == null) {
      _message('Discover tracks do not have a server folder.');
      return;
    }
    if (_track.volume == null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FileManagerScreen(api: api, initialPath: _folder),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StorageBrowserScreen(
          api: api,
          initialVolume: _track.volume,
          initialPath: _folder,
        ),
      ));
    }
  }

  Future<void> _toggleShuffle() async {
    try {
      await _player.setShuffle(!_player.state.shuffle);
    } catch (_) {
      _message('Could not change shuffle mode.');
    }
  }

  Future<void> _cycleRepeat() async {
    final next = switch (_player.state.playlistMode) {
      PlaylistMode.none => PlaylistMode.loop,
      PlaylistMode.loop => PlaylistMode.single,
      PlaylistMode.single => PlaylistMode.none,
    };
    try {
      await _player.setPlaylistMode(next);
    } catch (_) {
      _message('Could not change repeat mode.');
    }
  }

  Future<void> _showQueue() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Up next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              for (var index = 0; index < _persistent.queue.length; index++)
                ListTile(
                  leading: Icon(
                    index == _persistent.currentIndex
                        ? Icons.equalizer_rounded
                        : Icons.music_note_rounded,
                    color: index == _persistent.currentIndex ? Colors.white : Colors.white54,
                  ),
                  title: Text(
                    _persistent.queue[index].title.replaceAll('_', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _persistent.queue[index].path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _player.jump(index);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatsForNerds() {
    const surfaceColor = Color(0xFF171717);
    final accentColor = Theme.of(context).colorScheme.primary;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.query_stats_rounded, color: accentColor),
                  const SizedBox(width: 10),
                  Text(
                    'Stats for nerds',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              StreamBuilder<Track>(
                stream: _player.stream.track,
                initialData: _player.state.track,
                builder: (context, trackSnapshot) {
                  final audioTrack =
                      (trackSnapshot.data ?? _player.state.track).audio;
                  return StreamBuilder<double?>(
                    stream: _player.stream.audioBitrate,
                    initialData: _player.state.audioBitrate,
                    builder: (context, bitrateSnapshot) =>
                        StreamBuilder<AudioParams>(
                      stream: _player.stream.audioParams,
                      initialData: _player.state.audioParams,
                      builder: (context, paramsSnapshot) {
                        final trackBitrate = audioTrack.bitrate;
                        final streamBitrate = bitrateSnapshot.data ??
                            _player.state.audioBitrate;
                        final bitrate = _formatBitrate(
                          trackBitrate != null && trackBitrate > 0
                              ? trackBitrate.toDouble()
                              : streamBitrate,
                        );
                        final sourceSampleRate = audioTrack.samplerate;
                        final outputSampleRate = paramsSnapshot.data?.sampleRate ??
                            _player.state.audioParams.sampleRate;
                        final sampleRate = sourceSampleRate != null &&
                                sourceSampleRate > 0
                            ? _formatSampleRate(sourceSampleRate)
                            : outputSampleRate != null && outputSampleRate > 0
                                ? '${_formatSampleRate(outputSampleRate)} (output)'
                                : 'Not available';
                        final rawCodec = audioTrack.codec?.trim();
                        final codec = rawCodec == null || rawCodec.isEmpty
                            ? 'Not available'
                            : rawCodec.toUpperCase();

                        return Column(
                          children: [
                            MediaInfoRow('Codec', codec),
                            const Divider(height: 18, color: Colors.white12),
                            MediaInfoRow('Bitrate', bitrate),
                            const Divider(height: 18, color: Colors.white12),
                            MediaInfoRow('Sample rate', sampleRate),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Values are reported by the media source. Some files and streams do not provide every detail.',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBitrate(double? bitsPerSecond) {
    if (bitsPerSecond == null ||
        !bitsPerSecond.isFinite ||
        bitsPerSecond <= 0) {
      return 'Not available';
    }
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
    }
    final kilobitsPerSecond = bitsPerSecond / 1000;
    final precision =
        kilobitsPerSecond == kilobitsPerSecond.roundToDouble() ? 0 : 1;
    return '${kilobitsPerSecond.toStringAsFixed(precision)} kbps';
  }

  String _formatSampleRate(int sampleRate) {
    final kilohertz = sampleRate / 1000;
    final precision = kilohertz == kilohertz.roundToDouble() ? 0 : 1;
    return '${kilohertz.toStringAsFixed(precision)} kHz';
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  Widget _moreMenuButton({double contentOpacity = 1}) => SizedBox(
        width: 40,
        height: 40,
        child: LiquidGlassPill(
          radius: BorderRadius.circular(20),
          intensity: contentOpacity,
          child: SmokedGlassPopoverMenu<String>(
            tooltip: 'More playback options',
            items: [
              const SmokedGlassPopoverMenuItem(value: 'queue', label: 'Queue', icon: Icons.queue_music_rounded),
              const SmokedGlassPopoverMenuItem(value: 'shuffle', label: 'Shuffle', icon: Icons.shuffle_rounded),
              const SmokedGlassPopoverMenuItem(value: 'repeat', label: 'Repeat', icon: Icons.repeat_rounded),
              if (widget.api != null || _track.localPath != null)
                const SmokedGlassPopoverMenuItem(value: 'share', label: 'Share', icon: Icons.ios_share_rounded, dividerBefore: true),
              const SmokedGlassPopoverMenuItem(value: 'play_next', label: 'Play next', icon: Icons.skip_next_rounded),
              const SmokedGlassPopoverMenuItem(value: 'add_queue', label: 'Add to queue', icon: Icons.playlist_add_rounded),
              if (widget.api != null)
                const SmokedGlassPopoverMenuItem(value: 'show_folder', label: 'Show in folder', icon: Icons.folder_open_rounded),
              if (widget.api != null || _track.localPath != null)
                const SmokedGlassPopoverMenuItem(value: 'file_info', label: 'File info', icon: Icons.info_outline_rounded),
              const SmokedGlassPopoverMenuItem(value: 'sleep_timer', label: 'Sleep timer', icon: Icons.bedtime_outlined),
              if (widget.api != null)
                const SmokedGlassPopoverMenuItem(value: 'download', label: 'Download track', icon: Icons.download_rounded),
              if (_cached)
                const SmokedGlassPopoverMenuItem(value: 'remove_cache', label: 'Remove from cache', icon: Icons.delete_sweep_outlined, destructive: true),
              if (AppSettings.instance.showStatsForNerds)
                const SmokedGlassPopoverMenuItem(value: 'stats', label: 'Stats for nerds', icon: Icons.query_stats_rounded, dividerBefore: true),
            ],
            onSelected: (value) {
              switch (value) {
                case 'queue': unawaited(_showQueue()); break;
                case 'shuffle': unawaited(_toggleShuffle()); break;
                case 'repeat': unawaited(_cycleRepeat()); break;
                case 'share': unawaited(_runOption(TrackOptionAction.share)); break;
                case 'play_next': unawaited(_runOption(TrackOptionAction.playNext)); break;
                case 'add_queue': unawaited(_runOption(TrackOptionAction.addToQueue)); break;
                case 'show_folder': unawaited(_runOption(TrackOptionAction.showInFolder)); break;
                case 'file_info': unawaited(_runOption(TrackOptionAction.fileInfo)); break;
                case 'sleep_timer': unawaited(_runOption(TrackOptionAction.sleepTimer)); break;
                case 'download': unawaited(_runOption(TrackOptionAction.download)); break;
                case 'remove_cache': unawaited(_runOption(TrackOptionAction.removeFromCache)); break;
                case 'stats': _showStatsForNerds(); break;
              }
            },
            child: Opacity(
              opacity: contentOpacity,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      );

  Widget _header({double contentOpacity = 1}) => SizedBox(
        height: 86,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              _roundAction(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Minimize player',
                onTap: widget.onDismiss,
                contentOpacity: contentOpacity,
              ),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'PLAYING FROM ${_track.sourceLabel.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 9, letterSpacing: 1.15,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 12), Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xE9000000),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: SizedBox(
                          width: 21, height: 21,
                          child: TrackArtworkView(
                            bytes: _artworkKey == _trackKey ? _artwork : null,
                            artworkUrl: _track.artworkUrl,
                            fallbackColors: _trackPalette,
                            fallbackIconSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<bool>(
                        stream: _player.stream.playing,
                        initialData: _player.state.playing,
                        builder: (context, snapshot) {
                          final playing = snapshot.data ?? false;
                          const heights = [7.0, 13.0, 9.0, 16.0, 10.0];
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              for (var index = 0; index < heights.length; index++)
                                AnimatedContainer(
                                  duration: Duration(milliseconds: 180 + index * 35),
                                  curve: Curves.easeInOut,
                                  width: 2.5,
                                  height: playing ? heights[index] : 4,
                                  margin: const EdgeInsets.only(right: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ]),
                  ),
                ],
              ),
              const Spacer(),
              _moreMenuButton(contentOpacity: contentOpacity),
            ],
          ),
        ),
      );

  Widget _roundAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color foreground = Colors.white,
    double contentOpacity = 1,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: LiquidGlassPill(
        radius: BorderRadius.circular(20),
        intensity: contentOpacity,
        child: Opacity(
          opacity: contentOpacity,
          child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          padding: EdgeInsets.zero,
          iconSize: 19,
          style: IconButton.styleFrom(
            fixedSize: const Size(40, 40),
            shape: const CircleBorder(),
            backgroundColor: Colors.transparent,
            foregroundColor: foreground,
          ),
          icon: Icon(icon),
          ),
        ),
      ),
    );
  }

  Widget _timeline() => StreamBuilder<Duration>(
    stream: _player.stream.position,
    initialData: _player.state.position,
    builder: (context, positionSnapshot) => StreamBuilder<Duration>(
      stream: _player.stream.duration,
      initialData: _player.state.duration,
      builder: (context, durationSnapshot) => StreamBuilder<Duration>(
        stream: _player.stream.buffer,
        initialData: _player.state.buffer,
        builder: (context, bufferSnapshot) => StreamBuilder<bool>(
          stream: _player.stream.buffering,
          initialData: _player.state.buffering,
          builder: (context, bufferingSnapshot) => StreamBuilder<bool>(
            stream: _player.stream.playing,
            initialData: _player.state.playing,
            builder: (context, playingSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              final position = duration > Duration.zero
                  ? positionSnapshot.data ?? Duration.zero
                  : Duration.zero;
              return AnimatedBuilder(
                animation: AppSettings.instance,
                builder: (context, _) => NowPlayingScrubber(
                  style: NowPlayingScrubberStyle.appleCapsule,
                  position: position,
                  duration: duration,
                  bufferedPosition: bufferSnapshot.data ?? Duration.zero,
                  isPlaying: playingSnapshot.data ?? false,
                  isBuffering: bufferingSnapshot.data ?? false,
                  onSeek: (value) => unawaited(_player.seek(value)),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _transport() => NowPlayingTransportControls(
        playing: _player.stream.playing,
        buffering: _player.stream.buffering,
        duration: _player.stream.duration,
        initialPlaying: _player.state.playing,
        initialBuffering: _player.state.buffering,
        initialDuration: _player.state.duration,
        selectionLoading: () => _persistent.isSelectionLoading,
        hasMultipleTracks: () => _persistent.queue.length > 1,
        onPrevious: _persistent.skipToPrevious,
        onPlayPause: _player.playOrPause,
        onNext: _persistent.skipToNext,
      );

  Widget _bottomUtilities({bool lyricsActive = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _utilityButton(icon: Icons.lyrics_rounded, label: 'Lyrics',
              selected: lyricsActive, onTap: () => unawaited(_showTrackLyrics())),
            _utilityButton(icon: Icons.cast_rounded, label: 'Audio Output',
              onTap: _showAudioOutput),
            _utilityButton(icon: Icons.queue_music_rounded, label: 'Queue',
              onTap: _showQueue),
          ],
        ),
      );

  Widget _utilityButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 32,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: selected ? Colors.black : Colors.white),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: selected ? Colors.white : Colors.white60)),
        ]),
      );

  Future<void> _showTrackLyrics() async {
    if (_lyricsController.status == AnimationStatus.reverse) {
      unawaited(_lyricsController.forward());
      return;
    }
    if (_lyricsController.status == AnimationStatus.forward ||
        _lyricsController.value > 0.5) {
      // Keep the resolved document and provider state alive while the lyrics
      // view animates out; clearing it here flashes the unavailable state.
      await _lyricsController.reverse();
      return;
    }
    unawaited(_lyricsController.forward());
    await _loadTrackLyrics();
  }

  Future<void> _loadLyricsPreference() async {
    try {
      final value = await _secureStorage.read(key: 'pocketlink.lyrics.translation.enabled');
      if (mounted) setState(() => _lyricsTranslationEnabled = value == 'true');
    } catch (_) {}
  }

  Future<void> _loadTrackLyrics({bool retry = false}) async {
    final query = LyricsTrackQuery(track: _track, api: widget.api);
    if (retry) {
      _lyricsRepository.cancel(query.key);
      if (mounted) {
        setState(() {
          _lyricsProviderStates = const {};
          _activeLyrics = null;
          _lyricsLoading = false;
        });
      }
    }
    if (_lyricsQueryKey == query.key &&
        (_lyricsLoading || _activeLyrics != null || _lyricsProviderStates.isNotEmpty)) {
      return;
    }

    setState(() {
      _lyricsQueryKey = query.key;
      _lyricsLoading = true;
      _activeLyrics = _lyricsRepository.current(query.key);
      _lyricsProviderStates = _lyricsRepository.resultsFor(query.key);
      if (_lyricsProviderStates.isEmpty) {
        _lyricsProviderStates = {
          for (final provider in _lyricsRepository.providers)
            provider.id: const LyricsProviderResult(LyricsLookupStatus.loading),
        };
      }
    });
    try {
      final states = await _lyricsRepository.lookup(query, onUpdate: (next) {
        if (!mounted || _lyricsQueryKey != query.key) return;
        final active = _lyricsRepository.current(query.key);
        setState(() {
          _lyricsProviderStates = next;
          if (active != null) _activeLyrics = active;
        });
      });
      if (!mounted || _lyricsQueryKey != query.key) return;
      setState(() {
        _lyricsProviderStates = states;
        _activeLyrics = _lyricsRepository.current(query.key);
        _lyricsLoading = false;
      });
    } catch (_) {
      if (mounted && _lyricsQueryKey == query.key) {
        setState(() => _lyricsLoading = false);
        _message('Could not load lyrics from available providers.');
      }
    }
  }

  Future<void> _chooseLyricsProvider() async {
    final key = _lyricsQueryKey;
    if (key == null) return;
    final selected = await showLyricsProviderSheet(
      context,
      providers: _lyricsRepository.providers,
      results: _lyricsProviderStates,
      activeProvider: _activeLyrics?.providerId,
    );
    if (selected == null || !mounted) return;
    final document = _lyricsRepository.select(key, selected);
    if (document != null) setState(() => _activeLyrics = document);
  }

  Future<void> _toggleLyricsTranslation() async {
    final next = !_lyricsTranslationEnabled;
    setState(() => _lyricsTranslationEnabled = next);
    try {
      await _secureStorage.write(key: 'pocketlink.lyrics.translation.enabled', value: next.toString());
    } catch (_) {
      if (mounted) _message('Could not save the lyrics display preference.');
    }
    if (mounted) {
      _message(next
          ? 'Translation is enabled when a translated lyric source is available.'
          : 'Original lyrics displayed.');
    }
  }

  Widget _lyricsArtwork(double progress) {
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    final palette = _trackPalette;
    return ClipRRect(
      borderRadius: BorderRadius.lerp(
        BorderRadius.circular(26),
        BorderRadius.circular(10),
        progress,
      )!,
      child: hasArtwork
          ? Image.memory(_artwork!, cacheWidth: 544, fit: BoxFit.cover, gaplessPlayback: true)
          : DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [palette[0], palette[1], palette[2]])),
              child: const Center(child: Icon(Icons.music_note_rounded, color: Colors.white, size: 34)),
            ),
    );
  }

  Widget _lyricsMode(double progress) {
    return NowPlayingLyricsMode(
      progress: progress,
      artwork: _lyricsArtwork(progress),
      trackTitle: _fileName,
      artistLabel: cleanMediaArtist(_track.artist, fallback: _folderName),
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roundAction(
            icon: _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            tooltip: 'Favorite',
            foreground: _isFavorite ? const Color(0xFFFFD66B) : Colors.white,
            onTap: () => unawaited(_toggleFavorite()),
            contentOpacity: progress,
          ),
          const SizedBox(width: 6),
          _moreMenuButton(contentOpacity: progress),
        ],
      ),
      onClose: () => unawaited(_showTrackLyrics()),
      lyricsContent: StreamBuilder<Duration>(
        stream: _player.stream.position,
        initialData: _player.state.position,
        builder: (context, snapshot) => LyricsViewport(
          key: _lyricsViewportKey,
          document: _activeLyrics,
          position: snapshot.data ?? Duration.zero,
          loading: _lyricsLoading,
          results: _lyricsProviderStates,
          providers: _lyricsRepository.providers,
          onSeek: (position) => unawaited(_player.seek(position)),
          onChooseProvider: _chooseLyricsProvider,
          onToggleTranslation: _toggleLyricsTranslation,
          onRetry: () => unawaited(_loadTrackLyrics(retry: true)),
          translationEnabled: _lyricsTranslationEnabled,
        ),
      ),
      providerLabel: _activeLyrics == null ? '' : 'Lyrics by ${_activeLyrics!.providerName}',
      onChooseProvider: _chooseLyricsProvider,
      footer: const SizedBox(height: _playerChromeHeight),
    );
  }

  Widget _trackMetadata({double contentOpacity = 1}) {
    final artist = cleanMediaArtist(_track.artist, fallback: _track.sourceLabel);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Opacity(
              opacity: contentOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fileName, maxLines: 2, softWrap: true, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 25, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.55),
                  ),
                  const SizedBox(height: 5),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const style = TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500);
                      final painter = TextPainter(
                        text: TextSpan(text: artist, style: style),
                        maxLines: 1,
                        textDirection: Directionality.of(context),
                      )..layout(maxWidth: constraints.maxWidth);
                      final child = Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
                      if (!painter.didExceedMaxLines && painter.width <= constraints.maxWidth) return child;
                      return ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft, end: Alignment.centerRight,
                          colors: [Colors.white, Colors.white, Colors.transparent],
                          stops: [0, 0.72, 1],
                        ).createShader(bounds),
                        child: child,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _roundAction(
            icon: _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            tooltip: _isFavorite ? 'Remove favorite' : 'Favorite',
            foreground: _isFavorite ? const Color(0xFFFFD66B) : Colors.white,
            onTap: () => unawaited(_toggleFavorite()), contentOpacity: contentOpacity,
          ),
        ],
      ),
    );
  }

  Widget _lyricPreview() => StreamBuilder<Duration>(
        stream: _player.stream.position,
        initialData: _player.state.position,
        builder: (context, snapshot) {
          final lines = _activeLyrics?.lines ?? const <LyricsLine>[];
          final position = snapshot.data?.inMilliseconds ?? 0;
          final index = _activeLyrics?.synced == true
              ? lines.lastIndexWhere((line) => line.timeMs <= position)
              : 0;
          final preview = lines.isEmpty
              ? (_lyricsLoading ? 'Finding lyrics…' : 'Tap to view lyrics')
              : lines[index < 0 ? 0 : index].text;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => unawaited(_showTrackLyrics()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.lyrics_rounded, color: Colors.white54, size: 17),
                  const SizedBox(width: 10),
                  Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 19),
                ]),
              ),
            ),
          );
        },
      );

  Widget _volumeControl() => StreamBuilder<double>(
        stream: _player.stream.volume,
        initialData: _player.state.volume,
        builder: (context, snapshot) {
          final volume = (snapshot.data ?? 100).clamp(0.0, 100.0).toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 19),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0, max: 100, value: volume,
                    onChanged: (value) => unawaited(_player.setVolume(value)),
                  ),
                ),
              ),
              const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 19),
            ]),
          );
        },
      );

  Future<void> _showAudioOutput() async {
    final deviceName = _outputDeviceLabel;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Audio output', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smartphone_rounded, color: Colors.white),
              title: Text(deviceName, style: const TextStyle(color: Colors.white)),
              subtitle: const Text('Current device · managed by Android', style: TextStyle(color: Colors.white54)),
              trailing: const Icon(Icons.check_circle_rounded, color: Colors.white),
            ),
            const Text('To switch to Bluetooth or a cast device, use Android’s media output selector.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _playerDetails({double contentOpacity = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _trackMetadata(contentOpacity: contentOpacity),
          const SizedBox(height: 12),
          Opacity(opacity: contentOpacity, child: _lyricPreview()),
        ]),
      );

  /// One persistent lower chrome instance shared by Artwork and Lyrics modes.
  Widget _playerChrome() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _timeline(),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _transport(),
          ),
          const SizedBox(height: 5),
          _volumeControl(),
          const SizedBox(height: 3),
          _bottomUtilities(lyricsActive: _lyricsController.value > 0.5),
          const SizedBox(height: 3),
          Text(
            _outputDeviceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ]),
      );

  Widget _playerLayout(double contentOpacity, {required bool isMorphing}) {
    final heroHeight = MediaQuery.sizeOf(context).height * 0.46;
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!isMorphing) Positioned.fill(child: _ambientBackground()),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 190,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: .45), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0, left: 0, right: 0, height: heroHeight,
          child: SizedBox(
            key: widget.artworkTargetKey,
            width: double.infinity,
            child: isMorphing
                ? const SizedBox.expand()
                : TrackArtworkView(
                    bytes: hasArtwork ? _artwork : null,
                    artworkUrl: _track.artworkUrl,
                    fallbackColors: _trackPalette,
                    fallbackIconSize: 92,
                    fadeBottom: true,
                  ),
          ),
        ),
        if (isMorphing && hasArtwork)
          Positioned(
            top: heroHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
                child: Opacity(
                  opacity: 0.42,
                  child: Image.memory(
                    _artwork!,
                    cacheWidth: 720,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        if (isMorphing)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color.lerp(_trackPalette[0], const Color(0xFFB65D38), 0.24)!.withValues(alpha: 0.36),
                    Color.lerp(_trackPalette[1], const Color(0xFF6D3427), 0.30)!.withValues(alpha: 0.66),
                    Color.lerp(_trackPalette[2], const Color(0xFF160D0B), 0.28)!.withValues(alpha: 0.92),
                    const Color(0xF5000000),
                  ],
                  stops: const [0, 0.34, 0.48, 0.64, 0.84, 1],
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(children: [
            if (_lyricsController.value < 0.42)
              _header(contentOpacity: contentOpacity),
            const Spacer(),
            _playerDetails(
              contentOpacity: contentOpacity *
                  (1 - const Interval(0.30, 0.44, curve: Curves.easeInCubic)
                      .transform(_lyricsController.value)),
            ),
            const SizedBox(height: _playerChromeHeight),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.morphAnimation;
    final listenables = <Listenable>[AppSettings.instance, _lyricsController];
    if (animation != null) listenables.add(animation);
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final progress = animation?.value ?? 1.0;
        final contentOpacity = const Interval(
          0.55,
          1.0,
          curve: Curves.easeOutCubic,
        ).transform(progress);
        final isMorphing = widget.morphAnimation != null;
        return Scaffold(
          // The morph sheet owns the opaque backdrop. Keep this route
          // transparent while morphing so its shared artwork remains visible
          // behind the foreground title, badges and controls.
          backgroundColor: isMorphing
              ? Colors.transparent
              : const Color(0xFF0A0B0E),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (!isMorphing)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF0A0B0E)),
                ),
              Positioned.fill(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      ignoring: _lyricsController.value >= 0.42,
                      child: Opacity(
                        opacity: 1 - const Interval(
                          0.0,
                          0.52,
                          curve: Curves.easeInCubic,
                        ).transform(_lyricsController.value),
                        child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: AppSettings.instance.enableNowPlayingGestures
                      ? (_) => widget.onDismissDragStart()
                      : null,
                  onVerticalDragUpdate: AppSettings.instance.enableNowPlayingGestures
                      ? (details) => widget.onDismissDragUpdate(details.primaryDelta ?? 0)
                      : null,
                  onHorizontalDragStart: AppSettings.instance.enableNowPlayingGestures
                      ? (_) => _trackSwipeDistance = 0
                      : null,
                  onHorizontalDragUpdate: AppSettings.instance.enableNowPlayingGestures
                      ? (details) => _trackSwipeDistance += details.primaryDelta ?? 0
                      : null,
                  onVerticalDragEnd: AppSettings.instance.enableNowPlayingGestures
                      ? (details) => widget.onDismissDragEnd(details.primaryVelocity ?? 0)
                      : null,
                  onVerticalDragCancel: AppSettings.instance.enableNowPlayingGestures
                      ? () => widget.onDismissDragEnd(0)
                      : null,
                  onHorizontalDragEnd: AppSettings.instance.enableNowPlayingGestures
                      ? (details) {
                          final distance = _trackSwipeDistance;
                          final velocity = details.primaryVelocity ?? 0;
                          if (distance < -80 || velocity < -500) {
                            unawaited(_persistent.skipToNext());
                          } else if (distance > 80 || velocity > 500) {
                            unawaited(_persistent.skipToPrevious());
                          }
                          _trackSwipeDistance = 0;
                        }
                      : null,
                  // The artwork remains edge-to-edge; only player controls
                  // are inset by SafeArea inside _playerLayout.
                  child: _playerLayout(contentOpacity, isMorphing: isMorphing),
                    ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: _lyricsController.value <= 0.30,
                        child: Opacity(
                          opacity: const Interval(
                            0.30,
                            1.0,
                            curve: Curves.easeOutCubic,
                          ).transform(_lyricsController.value),
                          child: NowPlayingScrollDismissDetector(
                            enabled: AppSettings.instance.enableNowPlayingGestures,
                            onDismissDragStart: widget.onDismissDragStart,
                            onDismissDragUpdate: widget.onDismissDragUpdate,
                            onDismissDragEnd: widget.onDismissDragEnd,
                            scrollableKey: _lyricsViewportKey,
                            child: _lyricsMode(_lyricsController.value),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: _playerChrome(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_playlistSubscription?.cancel());
    _lyricsRepository.cancelAll();
    _lyricsController.dispose();
    super.dispose();
  }
}
