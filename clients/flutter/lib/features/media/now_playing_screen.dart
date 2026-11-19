import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/offline_file_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';
import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../storage/storage_browser_screen.dart';
import 'now_playing_scrubber.dart';
import 'persistent_audio_player.dart';
import 'track_options_sheet.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({
    required this.api,
    required this.queue,
    this.initialIndex = 0,
    this.resumeExisting = false,
    required this.onDismiss,
    required this.onDismissDragStart,
    required this.onDismissDragUpdate,
    required this.onDismissDragEnd,
    super.key,
  });

  final ServerApi api;
  final VoidCallback onDismiss;
  final VoidCallback onDismissDragStart;
  final ValueChanged<double> onDismissDragUpdate;
  final ValueChanged<double> onDismissDragEnd;
  final List<MediaQueueItem> queue;
  final int initialIndex;
  final bool resumeExisting;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  static const _artworkPalettes = <List<Color>>[
    [Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFF140B20)],
    [Color(0xFF0E7490), Color(0xFF2563EB), Color(0xFF07151F)],
    [Color(0xFFB45309), Color(0xFFBE185D), Color(0xFF1C100C)],
    [Color(0xFF4338CA), Color(0xFF0F766E), Color(0xFF0B1020)],
    [Color(0xFFBE185D), Color(0xFF4F46E5), Color(0xFF160B1E)],
  ];

  static const _secureStorage = FlutterSecureStorage();

  late final PersistentAudioPlayer _persistent;
  late final Player _player;
  StreamSubscription<Playlist>? _playlistSubscription;
  Uint8List? _artwork;
  String? _artworkKey;
  int _artworkRequest = 0;
  bool _cached = false;
  Set<String> _favorites = <String>{};
  double _trackSwipeDistance = 0;


  MediaQueueItem get _track =>
      _persistent.currentItem ??
      widget.queue[widget.initialIndex.clamp(0, widget.queue.length - 1).toInt()];

  String get _trackKey =>
      '${widget.api.baseUrl}|${_track.volume ?? 'internal'}:${_track.path}';

  String get _favoriteId => '${_track.volume ?? 'internal'}:${_track.path}';

  String get _favoriteStorageKey =>
      'pocketlink.music.favorites.${Uri.encodeComponent(widget.api.baseUrl)}';

  String get _legacyFavoriteStorageKey =>
      'homeserver.music.favorites.${Uri.encodeComponent(widget.api.baseUrl)}';

  bool get _isFavorite => _favorites.contains(_favoriteId);

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

  List<Color> get _trackPalette {
    final index = (_track.path.hashCode & 0x7fffffff) % _artworkPalettes.length;
    return _artworkPalettes[index];
  }

  Widget _ambientBackground() {
    final palette = _trackPalette;
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 680),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.72),
          radius: 1.4,
          colors: [
            palette[0].withValues(alpha: 0.40),
            palette[1].withValues(alpha: 0.25),
            palette[2].withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.88),
          ],
          stops: const [0, 0.38, 0.72, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArtwork)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
              child: Opacity(
                opacity: 0.34,
                child: Image.memory(
                  _artwork!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.46),
                  Colors.black.withValues(alpha: 0.78),
                ],
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
    _persistent = PersistentAudioPlayer.instance;
    _player = _persistent.player;
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
    final cached = await OfflineFileCache().find(
      OfflineFileCache().serverId(widget.api),
      _track.volume,
      _track.path,
    );
    if (mounted) setState(() => _cached = cached != null);
  }

  Future<void> _onTrackChanged() async {
    if (!mounted) return;
    setState(() {
      _artwork = null;
      _artworkKey = null;
    });
    await Future.wait([
      _refreshCacheStatus(),
      _loadArtwork(),
    ]);
  }

  Future<void> _loadArtwork() async {
    final request = ++_artworkRequest;
    final key = _trackKey;
    if (_track.localPath != null || _folder.isEmpty) {
      if (mounted) setState(() { _artwork = null; _artworkKey = key; });
      return;
    }

    // PocketLink currently exposes raw files, not embedded-artwork metadata.
    // Use an existing folder cover file when present; otherwise show the
    // compact artwork fallback rather than a blank full-height region.
    try {
      final listing = _track.volume == null
          ? await widget.api.listDirectory(_folder)
          : await widget.api.listStorageDirectory(_track.volume!, _folder);
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
            ? await widget.api.downloadFile(path)
            : await widget.api.downloadStorageFile(_track.volume!, path);
        if (!mounted || request != _artworkRequest) return;
        if (bytes.isNotEmpty) {
          setState(() { _artwork = bytes; _artworkKey = key; });
          return;
        }
      }
    } catch (_) {
      // Artwork is optional; playback must not depend on it.
    }
    if (mounted && request == _artworkRequest) {
      setState(() { _artwork = null; _artworkKey = key; });
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
        await OfflineFileCache().remove(
          OfflineFileCache().serverId(widget.api),
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
    final bytes = _track.volume == null
        ? await widget.api.downloadFile(_track.path)
        : await widget.api.downloadStorageFile(_track.volume!, _track.path);
    if (bytes.isEmpty) throw StateError('The server returned an empty file.');
    return bytes;
  }

  Future<void> _downloadTrack() async {
    try {
      final bytes = await _fileBytes();
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save original audio file',
        fileName: _track.path.split('/').last,
        bytes: bytes,
      );
      if (saved != null) _message('Original file saved.');
    } catch (_) {
      _message('Could not download this track.');
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
    try {
      final listing = _track.volume == null
          ? await widget.api.listDirectory(_folder)
          : await widget.api.listStorageDirectory(_track.volume!, _folder);
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
              _InfoLine('Filename', fileName),
              _InfoLine('Format', _formatTag),
              _InfoLine(
                'Size',
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Reading…'
                    : snapshot.data == null
                        ? 'Unavailable'
                        : _formatBytes(snapshot.data!),
              ),
              _InfoLine('Server path', _track.path),
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
    if (_track.volume == null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FileManagerScreen(api: widget.api, initialPath: _folder),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StorageBrowserScreen(
          api: widget.api,
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

  void _showOptions() {
    TrackOptionsSheet.show(
      context,
      isFavorite: _isFavorite,
      isCached: _cached,
      onAction: (action) => unawaited(_runOption(action)),
    );
  }

  void _showStatsForNerds() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.query_stats_rounded, color: Color(0xFFD8C9FF)),
                  SizedBox(width: 10),
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
                            _InfoLine('Codec', codec),
                            const Divider(height: 18, color: Colors.white12),
                            _InfoLine('Bitrate', bitrate),
                            const Divider(height: 18, color: Colors.white12),
                            _InfoLine('Sample rate', sampleRate),
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

  Widget _header() => SizedBox(
    height: 64,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _roundAction(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Minimize player',
          onTap: widget.onDismiss),
        const SizedBox(width: 12),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 34, height: 4, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.42), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 7),
          Text('PLAYING FROM ${_folderName.toUpperCase()}', textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(width: 12),
        SizedBox(width: 40, height: 40, child: LiquidGlassPill(
          radius: BorderRadius.circular(20),
          child: SmokedGlassPopoverMenu<String>(
            tooltip: 'Quick destinations',
            items: [
              const SmokedGlassPopoverMenuItem(value: 'home', label: 'Home', icon: Icons.home_outlined),
              const SmokedGlassPopoverMenuItem(value: 'queue', label: 'Queue', icon: Icons.queue_music_rounded),
              if (AppSettings.instance.showStatsForNerds)
                const SmokedGlassPopoverMenuItem(value: 'stats', label: 'Stats for nerds', icon: Icons.query_stats_rounded),
              const SmokedGlassPopoverMenuItem(value: 'track_options', label: 'Track options', icon: Icons.more_horiz_rounded),
            ],
            onSelected: (value) {
              switch (value) {
                case 'home': PocketLinkAppBar.goToDashboard(context); break;
                case 'stats': _showStatsForNerds(); break;
                case 'track_options': _showOptions(); break;
                case 'queue': _showQueue(); break;
              }
            },
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.grid_view_rounded, color: Colors.white, size: 19),
            ),
          ),
        )),
      ]),
    ),
  );

  Widget _artworkCard() {
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    final palette = _trackPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 40).clamp(0.0, 380.0).toDouble();
        final height = (constraints.maxHeight - 18).clamp(0.0, 380.0).toDouble();
        final dimension = math.min(width, height).clamp(0.0, 360.0).toDouble();
        return Container(
          width: dimension,
          height: dimension,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: palette[0].withValues(alpha: 0.28),
                blurRadius: 38,
                spreadRadius: 2,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: hasArtwork
                ? Stack(
                    key: ValueKey(_artworkKey),
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        _artwork!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.55, -0.7),
                            radius: 1.1,
                            colors: [
                              Colors.white.withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : DecoratedBox(
                    key: const ValueKey('music-artwork-fallback'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette[0].withValues(alpha: 0.92),
                          palette[1].withValues(alpha: 0.78),
                          palette[2],
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.music_note_rounded,
                        size: 92,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color foreground = Colors.white,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: LiquidGlassPill(
        radius: BorderRadius.circular(20),
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
                  style: NowPlayingScrubberStyle.fromKey(
                    AppSettings.instance.nowPlayingScrubberStyle,
                  ),
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

  Widget _transport() => StreamBuilder<bool>(
    stream: _player.stream.playing,
    initialData: _player.state.playing,
    builder: (context, playingSnapshot) => StreamBuilder<bool>(
      stream: _player.stream.buffering,
      initialData: _player.state.buffering,
      builder: (context, bufferingSnapshot) => StreamBuilder<Duration>(
        stream: _player.stream.duration,
        initialData: _player.state.duration,
        builder: (context, durationSnapshot) {
          final playing = playingSnapshot.data ?? false;
          final loading = (bufferingSnapshot.data ?? false) ||
              (durationSnapshot.data ?? Duration.zero) <= Duration.zero;
          final hasMultiple = _persistent.queue.length > 1;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _TransportGlyph(
                tooltip: 'Previous track',
                icon: Icons.skip_previous_rounded,
                size: 32,
                enabled: hasMultiple,
                onTap: _persistent.skipToPrevious,
              ),
              PlaybackLoadingIndicator(
                loading: loading,
                size: 68,
                child: _TransportGlyph(
                  tooltip: playing ? 'Pause' : 'Play',
                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 48,
                  enabled: true,
                  onTap: _player.playOrPause,
                ),
              ),
              _TransportGlyph(
                tooltip: 'Next track',
                icon: Icons.skip_next_rounded,
                size: 32,
                enabled: hasMultiple,
                onTap: _persistent.skipToNext,
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _bottomUtilities() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      StreamBuilder<bool>(
        stream: _player.stream.shuffle,
        initialData: _player.state.shuffle,
        builder: (context, snapshot) => IconButton(
          tooltip: 'Shuffle',
          onPressed: () => unawaited(_toggleShuffle()),
          iconSize: 22,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          icon: Icon(
            Icons.shuffle_rounded,
            color: (snapshot.data ?? false) ? Colors.white : Colors.white54,
          ),
        ),
      ),
      const SizedBox(width: 28),
      StreamBuilder<PlaylistMode>(
        stream: _player.stream.playlistMode,
        initialData: _player.state.playlistMode,
        builder: (context, snapshot) {
          final mode = snapshot.data ?? PlaylistMode.none;
          return IconButton(
            tooltip: 'Repeat',
            onPressed: () => unawaited(_cycleRepeat()),
            iconSize: 22,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints.tightFor(width: 42, height: 42),
            icon: Icon(
              mode == PlaylistMode.single
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: mode != PlaylistMode.none ? Colors.white : Colors.white54,
            ),
          );
        },
      ),
      const SizedBox(width: 28),
      IconButton(
        tooltip: 'Queue',
        onPressed: _showQueue,
        iconSize: 22,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        icon: const Icon(Icons.queue_music_rounded, color: Colors.white54),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0E),
      body: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF0A0B0E)),
              ),
              Positioned.fill(child: _ambientBackground()),
              Positioned.fill(
                child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: AppSettings.instance.enableNowPlayingGestures
            ? (_) => widget.onDismissDragStart()
            : null,
        onVerticalDragUpdate: AppSettings.instance.enableNowPlayingGestures
            ? (details) => widget.onDismissDragUpdate(details.primaryDelta ?? 0)
            : null,
        onHorizontalDragStart: AppSettings.instance.enableNowPlayingGestures ? (_) => _trackSwipeDistance = 0 : null,
        onHorizontalDragUpdate: AppSettings.instance.enableNowPlayingGestures ? (details) => _trackSwipeDistance += details.primaryDelta ?? 0 : null,
        onVerticalDragEnd: AppSettings.instance.enableNowPlayingGestures
            ? (details) => widget.onDismissDragEnd(details.primaryVelocity ?? 0)
            : null,
        onVerticalDragCancel: AppSettings.instance.enableNowPlayingGestures
            ? () => widget.onDismissDragEnd(0)
            : null,
        onHorizontalDragEnd: AppSettings.instance.enableNowPlayingGestures ? (details) {
          final distance = _trackSwipeDistance;
          final velocity = details.primaryVelocity ?? 0;
          if (distance < -80 || velocity < -500) {
            unawaited(_persistent.skipToNext());
          } else if (distance > 80 || velocity > 500) {
            unawaited(_persistent.skipToPrevious());
          }
          _trackSwipeDistance = 0;
        } : null,
        child: SafeArea(
          child: Column(
            children: [
            _header(),
            Expanded(
              child: Center(
                child: _artworkCard(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTag,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    letterSpacing: 1.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StreamBuilder<bool>(
                                  stream: _player.stream.buffering,
                                  initialData: _player.state.buffering,
                                  builder: (context, bufferingSnapshot) =>
                                      StreamBuilder<Duration>(
                                    stream: _player.stream.duration,
                                    initialData: _player.state.duration,
                                    builder: (context, durationSnapshot) {
                                      final loading =
                                          (bufferingSnapshot.data ?? false) ||
                                          (durationSnapshot.data ??
                                                  Duration.zero) <=
                                              Duration.zero;
                                      return AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        switchInCurve: Curves.easeOut,
                                        switchOutCurve: Curves.easeIn,
                                        child: loading
                                            ? const BufferingBadge(
                                                key: ValueKey('buffering'),
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey('ready'),
                                              ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _roundAction(
                        icon: _isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        tooltip: _isFavorite ? 'Remove favorite' : 'Favorite',
                        foreground: _isFavorite
                            ? const Color(0xFFFFD66B)
                            : Colors.white,
                        onTap: () => unawaited(_toggleFavorite()),
                      ),
                      const SizedBox(width: 8),
                      _roundAction(
                        icon: Icons.more_horiz_rounded,
                        tooltip: 'More options',
                        onTap: _showOptions,
                      ),
                    ],
                  ),
                  ... [
                    const SizedBox(height: 16),
                    _timeline(),
                  ],
                  ... [
                    const SizedBox(height: 16),
                    _transport(),
                  ],
                  ... [
                    
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _bottomUtilities(),
            const SizedBox(height: 2),
            const Text(
              'This device',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  ],
),
    );
  }

  @override
  void dispose() {
    unawaited(_playlistSubscription?.cancel());
    super.dispose();
  }
}

class _TransportGlyph extends StatefulWidget {
  const _TransportGlyph({required this.tooltip, required this.icon, required this.size, required this.enabled, required this.onTap});
  final String tooltip;
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onTap;
  @override
  State<_TransportGlyph> createState() => _TransportGlyphState();
}
class _TransportGlyphState extends State<_TransportGlyph> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Tooltip(message: widget.tooltip, child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.enabled ? widget.onTap : null,
    onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
    onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
    onTapCancel: () => setState(() => _pressed = false),
    child: SizedBox(width: 68, height: 68, child: Center(child: AnimatedScale(
      scale: _pressed ? 0.88 : 1, duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Icon(widget.icon, size: widget.size,
        color: Colors.white.withValues(alpha: widget.enabled ? 1 : 0.32)),
    ))),
  ));
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ],
    ),
  );
}
