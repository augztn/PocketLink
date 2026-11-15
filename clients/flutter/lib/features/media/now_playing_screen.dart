import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/offline_file_cache.dart';
import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../storage/storage_browser_screen.dart';
import 'persistent_audio_player.dart';
import 'track_options_sheet.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({
    required this.api,
    required this.queue,
    this.initialIndex = 0,
    this.resumeExisting = false,
    super.key,
  });

  final ServerApi api;
  final List<MediaQueueItem> queue;
  final int initialIndex;
  final bool resumeExisting;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  static const _secureStorage = FlutterSecureStorage();

  late final PersistentAudioPlayer _persistent;
  late final Player _player;
  StreamSubscription<Playlist>? _playlistSubscription;
  Uint8List? _artwork;
  String? _artworkKey;
  int _artworkRequest = 0;
  bool _cached = false;
  Set<String> _favorites = <String>{};
  double? _dragPosition;

  MediaQueueItem get _track =>
      _persistent.currentItem ??
      widget.queue[widget.initialIndex.clamp(0, widget.queue.length - 1).toInt()];

  String get _trackKey =>
      '${widget.api.baseUrl}|${_track.volume ?? 'internal'}:${_track.path}';

  String get _favoriteId => '${_track.volume ?? 'internal'}:${_track.path}';

  String get _favoriteStorageKey =>
      'homeserver.music.favorites.${Uri.encodeComponent(widget.api.baseUrl)}';

  bool get _isFavorite => _favorites.contains(_favoriteId);

  String get _fileName {
    final pathName = _track.path.split('/').last;
    final raw = _track.title.trim().isNotEmpty ? _track.title : pathName;
    return raw.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
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

  @override
  void initState() {
    super.initState();
    _persistent = PersistentAudioPlayer.instance;
    _player = _persistent.player;
    _persistent.setFullScreen(true);
    _playlistSubscription = _player.stream.playlist.listen((_) => _onTrackChanged());
    unawaited(_initialize());
    if (!widget.resumeExisting) {
      unawaited(_persistent.openQueue(
        api: widget.api,
        queue: widget.queue,
        initialIndex: widget.initialIndex,
        isMusic: true,
      ));
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
      final raw = await _secureStorage.read(key: _favoriteStorageKey);
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
      _dragPosition = null;
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

    // HomeServer currently exposes raw files, not embedded-artwork metadata.
    // Use an existing folder cover file when present; otherwise show the
    // compact artwork fallback rather than a blank full-height region.
    for (final name in const [
      'cover.jpg', 'cover.jpeg', 'cover.png', 'cover.webp',
      'folder.jpg', 'folder.png', 'album.jpg', 'album.png', 'front.jpg',
    ]) {
      final path = '$_folder/$name';
      try {
        final bytes = _track.volume == null
            ? await widget.api.downloadFile(path)
            : await widget.api.downloadStorageFile(_track.volume!, path);
        if (!mounted || request != _artworkRequest) return;
        if (bytes.isNotEmpty) {
          setState(() { _artwork = bytes; _artworkKey = key; });
          return;
        }
      } catch (_) {
        // Try the next conventional folder-cover filename.
      }
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
      final saved = await FilePicker.platform.saveFile(
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
      await Share.shareXFiles([
        XFile.fromData(bytes, name: _track.path.split('/').last),
      ], text: _fileName);
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

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 30);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
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
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: 'Close player',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'PLAYING FROM ${_folderName.toUpperCase()}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Home',
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_rounded, color: Colors.white70, size: 21),
                  visualDensity: VisualDensity.compact,
                ),
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 21),
                  onSelected: (_) => _showOptions(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'track_options', child: Text('Track options')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _artworkCard() {
    final hasArtwork = _artwork != null && _artworkKey == _trackKey;
    return Container(
      width: 230,
      height: 230,
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasArtwork
          ? Image.memory(_artwork!, fit: BoxFit.cover, gaplessPlayback: true)
          : const Center(
              child: Icon(
                Icons.music_note_rounded,
                size: 76,
                color: Colors.white70,
              ),
            ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color foreground = Colors.white,
  }) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 19,
        style: IconButton.styleFrom(
          fixedSize: const Size(38, 38),
          shape: const CircleBorder(),
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          foregroundColor: foreground,
        ),
        icon: Icon(icon),
      ),
    );
  }

  Widget _timeline() => StreamBuilder<Duration>(
    stream: _player.stream.position,
    initialData: _player.state.position,
    builder: (context, positionSnapshot) => StreamBuilder<Duration>(
      stream: _player.stream.duration,
      initialData: _player.state.duration,
      builder: (context, durationSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        final duration = durationSnapshot.data ?? Duration.zero;
        final max = duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
        final current = (_dragPosition ?? position.inMilliseconds.toDouble()).clamp(0, max).toDouble();
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                thumbColor: Colors.white,
              ),
              child: Slider(
                min: 0,
                max: max,
                value: current,
                onChangeStart: duration > Duration.zero
                    ? (value) => setState(() => _dragPosition = value)
                    : null,
                onChanged: duration > Duration.zero
                    ? (value) => setState(() => _dragPosition = value)
                    : null,
                onChangeEnd: duration > Duration.zero
                    ? (value) {
                        _player.seek(Duration(milliseconds: value.round()));
                        setState(() => _dragPosition = null);
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('-${_formatDuration(duration - position)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _transport() => StreamBuilder<bool>(
    stream: _player.stream.playing,
    initialData: _player.state.playing,
    builder: (context, snapshot) {
      final playing = snapshot.data ?? false;
      final hasMultiple = _persistent.queue.length > 1;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Previous track',
            onPressed: hasMultiple ? _player.previous : null,
            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
          ),
          IconButton(
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: _player.playOrPause,
            iconSize: 46,
            color: Colors.white,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: 'Next track',
            onPressed: hasMultiple ? _player.next : null,
            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
          ),
        ],
      );
    },
  );

  Widget _volume() => StreamBuilder<double>(
    stream: _player.stream.volume,
    initialData: _player.state.volume,
    builder: (context, snapshot) => Row(
      children: [
        const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 18),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              min: 0,
              max: 100,
              value: (snapshot.data ?? 100).clamp(0, 100).toDouble(),
              activeColor: Colors.white70,
              inactiveColor: Colors.white12,
              onChanged: _player.setVolume,
            ),
          ),
        ),
        const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 18),
      ],
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
      backgroundColor: Colors.black,
      body: SafeArea(
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
                  const SizedBox(height: 16),
                  _timeline(),
                  const SizedBox(height: 16),
                  _transport(),
                  const SizedBox(height: 12),
                  _volume(),
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
    );
  }

  @override
  void dispose() {
    unawaited(_playlistSubscription?.cancel());
    unawaited(_persistent.closePlayerScreen(isVideo: false));
    super.dispose();
  }
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
