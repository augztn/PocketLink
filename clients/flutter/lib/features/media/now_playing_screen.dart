import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/offline_file_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../core/settings/app_settings.dart';
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
  static const double _playerChromeHeight = 292;

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
  static final LyricsRepository _lyricsRepository = LyricsRepository();
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

  Widget _ambientBackground({bool lyricsMode = false}) {
    // Keep the same deterministic fallback palette used by the morph sheet
    // until the sheet reaches its final frame. Artwork extraction can finish
    // during the 300–400ms transition; revealing it mid-morph caused a
    // one-frame fallback-to-artwork color flash.
    final isMorphing = widget.morphAnimation != null &&
        widget.morphAnimation!.value < 0.999;
    final palette = isMorphing
        ? NowPlayingArtworkPalette.fallback(
            title: _track.title,
            folderName: _folderName,
            path: _track.path,
          )
        : _trackPalette;
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
            Color.lerp(palette[2], palette[1], 0.24)!,
            Color.lerp(palette[2], palette[1], 0.38)!,
          ],
          stops: const [0, 0.34, 0.70, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArtwork)
            RepaintBoundary(
              child: ImageFiltered(
                // A 48px decode keeps the ambient wash inexpensive to rasterize.
                // The sharp foreground artwork is painted separately below.
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 14,
                  sigmaY: 14,
                  tileMode: TileMode.mirror,
                ),
                child: Opacity(
                  opacity: 0.68,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      1.18, -0.09, -0.09, 0, 0,
                      -0.09, 1.18, -0.09, 0, 0,
                      -0.09, -0.09, 1.18, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
                    child: Image(
                      image: ResizeImage(
                        MemoryImage(_artwork!),
                        width: 48,
                        height: 48,
                      ),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          // Keep the ambient artwork continuous beneath the full-screen
          // sharp layer, including the bottom safe area.
          ColoredBox(color: Colors.black.withValues(alpha: lyricsMode ? 0.32 : 0.24)),
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
    unawaited(_loadTrackLyrics());
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
    unawaited(_loadTrackLyrics());
    await Future.wait([
      _refreshCacheStatus(),
      _loadArtwork(),
    ]);
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

  Widget _frostedCircle({
    required Widget child,
    required BorderRadius radius,
    double intensity = 1,
  }) {
    final transitioning = widget.morphAnimation != null &&
        widget.morphAnimation!.value < 0.999;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16 * intensity),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14 * intensity),
        ),
        borderRadius: radius,
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: radius,
      child: transitioning
          ? surface
          : BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 16 * intensity,
                sigmaY: 16 * intensity,
              ),
              child: surface,
            ),
    );
  }

  Widget _moreMenuButton({double contentOpacity = 1}) => SizedBox(
        width: 38,
        height: 38,
        child: _frostedCircle(
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
                width: 38,
                height: 38,
                child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              ),
            ),
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
      width: 38,
      height: 38,
      child: _frostedCircle(
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
            fixedSize: const Size(38, 38),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _utilityButton(icon: Icons.lyrics_rounded, label: 'Lyrics',
              selected: lyricsActive, onTap: () => unawaited(_showTrackLyrics())),
            _utilityButton(icon: Icons.cast_rounded, label: 'Audio Output',
              onTap: _showAudioOutput),
            _utilityButton(icon: Icons.queue_music_rounded, label: 'Queue',
              onTap: _showQueue),
            if (lyricsActive)
              LyricsTranslationControlPill(
                translationEnabled: _lyricsTranslationEnabled,
                onChooseProvider: _chooseLyricsProvider,
                onToggleTranslation: _toggleLyricsTranslation,
              ),
          ],
        ),
      );

  Widget _utilityButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) => Tooltip(
        message: label,
        child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: selected ? Colors.black : Colors.white),
          ),
        ]),
        ),
      );

  Future<void> _showTrackLyrics() async {
    if (!mounted) return;

    // Toggle from the visible state rather than AnimationStatus. A system
    // Back gesture can interrupt an in-flight transition, leaving status as
    // reverse/forward while the controller is already near the opposite end.
    if (_lyricsController.value >= 0.5) {
      await _lyricsController.reverse();
      return;
    }

    // Start the visual transition immediately; lyric lookup runs alongside it.
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

    final cachedStates = _lyricsRepository.resultsFor(query.key);
    final cachedDocument = _lyricsRepository.current(query.key);
    final hasCompletedCache = cachedStates.isNotEmpty &&
        cachedStates.values.every((value) => value.status != LyricsLookupStatus.loading);
    setState(() {
      _lyricsQueryKey = query.key;
      // Keep an already-resolved lyric document visible when other providers
      // are still enriching the cache in the background after a sheet reopen.
      _lyricsLoading = !hasCompletedCache && cachedDocument == null;
      _activeLyrics = cachedDocument;
      _lyricsProviderStates = cachedStates;
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
    final image = hasArtwork
        ? Image.memory(_artwork!, cacheWidth: 544, fit: BoxFit.cover, gaplessPlayback: true)
        : DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [palette[0], palette[1], palette[2]])),
            child: const Center(child: Icon(Icons.music_note_rounded, color: Colors.white, size: 34)),
          );
    return ClipRRect(
      borderRadius: BorderRadius.lerp(
        BorderRadius.circular(26),
        BorderRadius.circular(10),
        progress,
      )!,
      child: progress < 0.98
          ? ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.58, 1],
              ).createShader(bounds),
              child: image,
            )
          : image,
    );
  }

  Widget _lyricsMode(double progress) {
    return NowPlayingLyricsMode(
      progress: progress,
      background: _ambientBackground(lyricsMode: true),
      artwork: _lyricsArtwork(progress),
      trackTitle: _fileName,
      artistLabel: resolveMediaArtist(artist: _track.artist, title: _track.title, path: _track.path, fallback: _folderName),
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
          const SizedBox(width: 10),
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
    final artist = resolveMediaArtist(artist: _track.artist, title: _track.title, path: _track.path, fallback: _folderName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
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
                  _ArtworkTitleMarquee(
                    text: _fileName,
                    style: const TextStyle(color: Colors.white, fontSize: 22, height: 1.18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final style = TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 18, height: 1.2, fontWeight: FontWeight.w400);
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
          const SizedBox(width: 10),
          _roundAction(
            icon: _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            tooltip: _isFavorite ? 'Remove favorite' : 'Favorite',
            foreground: _isFavorite ? const Color(0xFFFFD66B) : Colors.white,
            onTap: () => unawaited(_toggleFavorite()), contentOpacity: contentOpacity,
          ),
          const SizedBox(width: 6),
          _moreMenuButton(contentOpacity: contentOpacity),
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
          final inInstrumentalGap = _activeLyrics?.synced == true &&
              (index < 0 || (index < lines.length - 1 && lines[index + 1].timeMs - position > 12000));
          final preview = inInstrumentalGap
              ? 'Instrumental'
              : lines.isEmpty
                  ? (_lyricsLoading ? 'Finding lyrics…' : 'Tap to view lyrics')
                  : lines[index < 0 ? 0 : index].text;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_showTrackLyrics()),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  if (inInstrumentalGap) ...[
                    const Icon(Icons.music_note_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: _lyricsLoading && lines.isEmpty
                        ? const _LyricsSearchingPulse()
                        : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 17, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 16),
                ]),
              ),
            ),
          );
        },
      );

  Widget _volumeControl() => StreamBuilder<double>(
        stream: _persistent.systemMediaVolumeStream,
        initialData: _persistent.systemMediaVolume,
        builder: (context, snapshot) {
          final volume = (snapshot.data ?? _persistent.systemMediaVolume)
              .clamp(0.0, 100.0)
              .toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 19),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: SliderComponentShape.noThumb,
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: Colors.white.withValues(alpha: 0.85),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0, max: 100, value: volume,
                    onChanged: (value) => unawaited(_persistent.setSystemMediaVolume(value)),
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
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _trackMetadata(contentOpacity: contentOpacity),
          const SizedBox(height: 18),
          Opacity(opacity: contentOpacity, child: _lyricPreview()),
        ]),
      );

  /// One persistent lower chrome instance shared by Artwork and Lyrics modes.
  Widget _playerChrome() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _timeline(),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _transport(),
          ),
          const SizedBox(height: 24),
          _volumeControl(),
          const SizedBox(height: 20),
          _bottomUtilities(lyricsActive: _lyricsController.value > 0.5),
          const SizedBox(height: 14),
          Text(
            _outputDeviceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ]),
      );

  Widget _playerLayout(double contentOpacity) {
    final heroHeight = MediaQuery.sizeOf(context).height * 0.56;
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _ambientBackground()),
        Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white,
                  Colors.white,
                  Color(0xCCFFFFFF),
                  Color(0x55FFFFFF),
                  Color(0x14FFFFFF),
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: [0.0, 0.34, 0.46, 0.56, 0.65, 0.74, 1.0],
              ).createShader(bounds),
              child: TrackArtworkView(
                bytes: hasArtwork ? _artwork : null,
                artworkUrl: _track.artworkUrl,
                fallbackColors: _trackPalette,
                fallbackIconSize: 92,
                fallbackAlignment: const Alignment(0, -0.42),
                fit: BoxFit.cover,
              ),
            ),
          ),
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: SizedBox(
              key: widget.artworkTargetKey,
              child: const SizedBox.expand(),
            ),
          ),
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
            top: MediaQuery.paddingOf(context).top,
            left: 0,
            right: 0,
            child: Center(
              child: Opacity(
                // The overlay paints the same handle outside its morph clip.
                // Keep this tap target active, but avoid drawing it twice.
                opacity: widget.morphAnimation == null ? 1 : 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_showTrackLyrics()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
                    child: Container(
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 17,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: Center(
              child: Text(
                'Playing from ${_track.sourceLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.90),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
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
        // The morph animation object remains attached for the route's entire
        // lifetime. Only use the clipped morph artwork while the controller is
        // actually between its collapsed and fully expanded states.
        return PopScope(
          // Back first exits the lyrics layer. Only pop Now Playing after
          // the lyrics transition has fully closed.
          canPop: _lyricsController.value <= 0.001,
          onPopInvoked: (didPop) {
            if (!didPop && _lyricsController.value > 0.001) {
              unawaited(_lyricsController.reverse());
            }
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
          // The morph sheet owns the opaque backdrop. Keep this route
          // transparent while morphing so its shared artwork remains visible
          // behind the foreground title, badges and controls.
          backgroundColor: const Color(0xFF0A0B0E),
          body: Stack(
            fit: StackFit.expand,
            children: [
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
                  child: _playerLayout(contentOpacity),
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
          ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_playlistSubscription?.cancel());
    _lyricsController.dispose();
    super.dispose();
  }
}


class _ArtworkTitleMarquee extends StatefulWidget {
  const _ArtworkTitleMarquee({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_ArtworkTitleMarquee> createState() => _ArtworkTitleMarqueeState();
}

class _ArtworkTitleMarqueeState extends State<_ArtworkTitleMarquee>
    with SingleTickerProviderStateMixin {
  static const double _gap = 36;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 8500),
  );

  @override
  void didUpdateWidget(covariant _ArtworkTitleMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout();
          final overflow = painter.width - constraints.maxWidth;
          if (overflow <= 1) {
            _controller.stop();
            _controller.value = 0;
            return Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
          }
          if (!_controller.isAnimating) _controller.repeat();
          final distance = painter.width + _gap;
          final scroll = TweenSequence<double>([
            TweenSequenceItem<double>(tween: ConstantTween<double>(0), weight: 1.5),
            TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: distance), weight: 7),
          ]).animate(_controller);
          // The mask must use the viewport width, not the duplicated text
          // strip width. Masking the strip itself makes the fade travel with
          // the text and leaves hard-clipped glyphs at the viewport edges.
          return SizedBox(
            width: constraints.maxWidth,
            height: painter.height,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: scroll.value > 0.001
                    ? const [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ]
                    : const [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                stops: const [0, 0.04, 0.90, 1],
              ).createShader(bounds),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: constraints.maxWidth,
                  maxWidth: double.infinity,
                  minHeight: painter.height,
                  maxHeight: painter.height,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Transform.translate(
                      offset: Offset(-scroll.value, 0),
                      child: SizedBox(
                        width: painter.width * 2 + _gap,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                            const SizedBox(width: _gap),
                            Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
class _LyricsSearchingPulse extends StatefulWidget {
  const _LyricsSearchingPulse();

  @override
  State<_LyricsSearchingPulse> createState() => _LyricsSearchingPulseState();
}

class _LyricsSearchingPulseState extends State<_LyricsSearchingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: .48, end: 1).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: const Text(
          'Searching lyrics…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
}
