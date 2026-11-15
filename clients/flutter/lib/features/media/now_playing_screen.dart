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

class _LyricLine {
  const _LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class _NowPlayingScreenState extends State<NowPlayingScreen> with SingleTickerProviderStateMixin {
  static const _storage = FlutterSecureStorage();
  static const _favoriteKey = 'homeserver.music.favorites.v1';
  static const _pinnedKey = 'homeserver.music.pinned.v1';
  static const _playlistKey = 'homeserver.music.playlists.v1';

  late final PersistentAudioPlayer _persistent;
  late final Player _player;
  StreamSubscription<Playlist>? _playlistSubscription;
  Uint8List? _artwork;
  String? _artworkKey;
  int _artworkRequest = 0;
  Set<String> _favorites = {};
  Set<String> _pinned = {};
  bool _favorite = false;
  bool _pinnedCurrent = false;
  bool _cached = false;
  bool _loadingLyrics = false;
  List<_LyricLine> _lyrics = [];
  Duration _lyricsOffset = Duration.zero;
  Timer? _sleepTimer;
  int? _sleepMinutes;
  double _dragPosition = 0;

  MediaQueueItem get _track => _persistent.currentItem ?? widget.queue[widget.initialIndex.clamp(0, widget.queue.length - 1).toInt()];
  String get _trackKey => '${_track.volume ?? 'internal'}:${_track.path}';
  String get _title => _track.title.replaceAll(RegExp(r'\\.[^.]+$'), '');
  String get _folder => _track.path.contains('/') ? _track.path.substring(0, _track.path.lastIndexOf('/')) : 'Internal storage';
  String get _folderName => _folder.isEmpty ? 'Internal storage' : _folder.split('/').last;

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
    await _loadStoredActions();
    await _refreshCacheStatus();
    await _loadArtwork();
    await _loadLyrics();
  }

  Future<void> _loadStoredActions() async {
    try {
      final favorites = jsonDecode(await _storage.read(key: _favoriteKey) ?? '[]') as List<dynamic>;
      final pinned = jsonDecode(await _storage.read(key: _pinnedKey) ?? '[]') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _favorites = favorites.whereType<String>().toSet();
        _pinned = pinned.whereType<String>().toSet();
        _favorite = _favorites.contains(_trackKey);
        _pinnedCurrent = _pinned.contains(_trackKey);
      });
    } catch (_) {
      // Invalid optional metadata must never interrupt playback.
    }
  }

  Future<void> _refreshCacheStatus() async {
    final cached = await OfflineFileCache().find(
      OfflineFileCache().serverId(widget.api), _track.volume, _track.path,
    );
    if (mounted) setState(() => _cached = cached != null);
  }

  Future<void> _onTrackChanged() async {
    if (!mounted) return;
    setState(() {
      _artwork = null;
      _artworkKey = null;
      _lyrics = [];
      _lyricsOffset = Duration.zero;
    });
    await _loadStoredActions();
    await _refreshCacheStatus();
    await _loadArtwork();
    await _loadLyrics();
  }

  Future<void> _loadArtwork() async {
    final request = ++_artworkRequest;
    final key = _trackKey;
    if (_track.localPath != null) {
      if (mounted) setState(() { _artwork = null; _artworkKey = key; });
      return;
    }
    for (final name in const [
      'cover.jpg', 'cover.jpeg', 'cover.png', 'cover.webp',
      'folder.jpg', 'folder.png', 'album.jpg', 'album.png', 'front.jpg',
    ]) {
      final path = _folder.isEmpty ? name : '$_folder/$name';
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
        // Continue through conventional artwork filenames.
      }
    }
    if (mounted && request == _artworkRequest) setState(() => _artworkKey = key);
  }

  Future<void> _loadLyrics() async {
    if (_track.localPath != null) {
      final file = File(_track.localPath!);
      final sibling = File('${file.parent.path}/${_track.title.replaceAll(RegExp(r'\\.[^.]+$'), '')}.lrc');
      if (await sibling.exists()) {
        await _parseLyrics(await sibling.readAsString());
      }
      return;
    }
    setState(() => _loadingLyrics = true);
    final path = _track.path.replaceAll(RegExp(r'\\.[^.]+$'), '') + '.lrc';
    try {
      final bytes = _track.volume == null
          ? await widget.api.downloadFile(path)
          : await widget.api.downloadStorageFile(_track.volume!, path);
      await _parseLyrics(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      if (mounted) setState(() => _lyrics = []);
    } finally {
      if (mounted) setState(() => _loadingLyrics = false);
    }
  }

  Future<void> _parseLyrics(String raw) async {
    final pattern = RegExp(r'^\\[(\\d{2}):(\\d{2})(?:[.\\:](\\d{1,3}))?\\](.*)$', multiLine: true);
    final parsed = pattern.allMatches(raw).map((match) {
      final fraction = (match.group(3) ?? '0').padRight(3, '0').substring(0, 3);
      return _LyricLine(
        Duration(
          minutes: int.parse(match.group(1)!),
          seconds: int.parse(match.group(2)!),
          milliseconds: int.parse(fraction),
        ),
        match.group(4)!.trim(),
      );
    }).where((line) => line.text.isNotEmpty).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (mounted) setState(() => _lyrics = parsed);
  }

  String _keyForCurrent() => _trackKey;

  Future<void> _toggleStored(Set<String> values, String key, String storageKey, bool favorite) async {
    final updated = Set<String>.from(values);
    if (!updated.add(key)) updated.remove(key);
    await _storage.write(key: storageKey, value: jsonEncode(updated.toList()));
    if (!mounted) return;
    setState(() {
      if (favorite) {
        _favorites = updated;
        _favorite = updated.contains(key);
      } else {
        _pinned = updated;
        _pinnedCurrent = updated.contains(key);
      }
    });
    _message(favorite ? (_favorite ? 'Added to favorites' : 'Removed from favorites') : (_pinnedCurrent ? 'Track pinned' : 'Pin removed'));
  }

  Future<void> _toggleFavorite() => _toggleStored(_favorites, _keyForCurrent(), _favoriteKey, true);
  Future<void> _togglePin() => _toggleStored(_pinned, _keyForCurrent(), _pinnedKey, false);

  Future<void> _runOption(TrackOptionAction action) async {
    switch (action) {
      case TrackOptionAction.favorite:
        await _toggleFavorite();
        break;
      case TrackOptionAction.pin:
        await _togglePin();
        break;
      case TrackOptionAction.share:
        await _shareTrack();
        break;
      case TrackOptionAction.addToPlaylist:
        await _addToPlaylist();
        break;
      case TrackOptionAction.playNext:
        await _persistent.enqueue(_track, playNext: true);
        _message('Queued to play next');
        break;
      case TrackOptionAction.addToQueue:
        await _persistent.enqueue(_track);
        _message('Added to queue');
        break;
      case TrackOptionAction.download:
        await _downloadTrack();
        break;
      case TrackOptionAction.removeFromCache:
        await OfflineFileCache().remove(OfflineFileCache().serverId(widget.api), _track.volume, _track.path);
        if (mounted) setState(() => _cached = false);
        _message('Removed local cached copy');
        break;
      case TrackOptionAction.openAlbum:
        _openAlbum();
        break;
      case TrackOptionAction.openArtist:
        _message('Artist metadata is not available from this server file entry.');
        break;
      case TrackOptionAction.showInFolder:
        _showInFolder();
        break;
      case TrackOptionAction.trackInfo:
        _showTrackInfo();
        break;
      case TrackOptionAction.sleepTimer:
        await _chooseSleepTimer();
        break;
      case TrackOptionAction.lyricsOffset:
        await _chooseLyricsOffset();
        break;
    }
  }

  Future<List<int>> _fileBytes() async {
    if (_track.localPath != null) return File(_track.localPath!).readAsBytes();
    return _track.volume == null
        ? widget.api.downloadFile(_track.path)
        : widget.api.downloadStorageFile(_track.volume!, _track.path);
  }

  Future<void> _downloadTrack() async {
    try {
      final bytes = Uint8List.fromList(await _fileBytes());
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save original track',
        fileName: _track.title,
        bytes: bytes,
      );
      if (saved != null) _message('Saved original file');
    } catch (_) {
      _message('Could not download this track.');
    }
  }

  Future<void> _shareTrack() async {
    try {
      final bytes = Uint8List.fromList(await _fileBytes());
      await Share.shareXFiles([XFile.fromData(bytes, name: _track.title)], text: _title);
    } catch (_) {
      _message('Could not share this track.');
    }
  }

  Future<void> _addToPlaylist() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202023),
        title: const Text('Add to playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Playlist name', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, nameController.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final raw = await _storage.read(key: _playlistKey);
      final playlists = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      final entries = (playlists[name] as List<dynamic>? ?? const []).whereType<String>().toList();
      if (!entries.contains(_trackKey)) entries.add(_trackKey);
      playlists[name] = entries;
      await _storage.write(key: _playlistKey, value: jsonEncode(playlists));
      _message('Added to $name');
    } catch (_) {
      _message('Could not save this playlist.');
    }
  }

  Future<void> _chooseSleepTimer() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Sleep timer', style: TextStyle(color: Colors.white))),
        for (final value in [15, 30, 45, 60, 90])
          ListTile(title: Text('$value minutes', style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, value)),
        if (_sleepTimer != null)
          ListTile(title: const Text('Cancel timer', style: TextStyle(color: Colors.white70)), onTap: () => Navigator.pop(ctx, 0)),
      ])),
    );
    if (minutes == null) return;
    _sleepTimer?.cancel();
    if (minutes == 0) {
      if (mounted) setState(() => _sleepMinutes = null);
      return;
    }
    setState(() => _sleepMinutes = minutes);
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _player.pause();
      if (mounted) setState(() => _sleepMinutes = null);
    });
  }

  Future<void> _chooseLyricsOffset() async {
    var value = _lyricsOffset.inMilliseconds.toDouble();
    final selected = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF202023),
        title: const Text('Lyrics offset', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${value >= 0 ? '+' : ''}${(value / 1000).toStringAsFixed(1)} s', style: const TextStyle(color: Colors.white70)),
          Slider(min: -5000, max: 5000, divisions: 100, value: value, onChanged: (v) => setDialogState(() => value = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('Apply')),
        ],
      )),
    );
    if (selected == null) return;
    setState(() => _lyricsOffset = Duration(milliseconds: selected.round()));
  }

  void _openAlbum() {
    if (_folder.isEmpty) {
      _message('No album folder is available for this track.');
    } else {
      _showInFolder();
    }
  }

  void _showInFolder() {
    if (_track.volume == null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FileManagerScreen(api: widget.api, initialPath: _folder),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StorageBrowserScreen(api: widget.api, initialVolume: _track.volume, initialPath: _folder),
      ));
    }
  }

  void _showTrackInfo() {
    final audioTrack = _player.state.track.audio;
    final extension = _track.title.contains('.') ? _track.title.split('.').last.toUpperCase() : 'Unknown';
    final codec = (audioTrack.codec?.trim().isNotEmpty ?? false) ? audioTrack.codec!.toUpperCase() : extension;
    final channels = _channelLabel(audioTrack.channels, audioTrack.channelscount);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202023),
        title: const Text('Track & file info', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _InfoLine('Format', codec),
          _InfoLine('Channels', channels?.isNotEmpty == true ? channels! : 'Not reported by source'),
          _InfoLine('Sample rate', audioTrack.samplerate == null ? 'Not reported' : '${(audioTrack.samplerate! / 1000).toStringAsFixed(1)} kHz'),
          _InfoLine('Bitrate', audioTrack.bitrate == null ? 'Not reported' : '${(audioTrack.bitrate! / 1000).round()} kbps'),
          _InfoLine('File size', _track.size == null ? 'Not provided' : _formatBytes(_track.size!)),
          _InfoLine('Server path', _track.path),
          _InfoLine('Source', _track.localPath == null ? 'Direct original stream' : 'Local offline copy'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _showLyrics() async {
    if (_lyrics.isEmpty) {
      await _loadLyrics();
      if (_lyrics.isEmpty) {
        _message('No matching .lrc lyrics file found.');
        return;
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101012),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.72,
          child: StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (ctx, snapshot) {
              final position = (snapshot.data ?? Duration.zero) - _lyricsOffset;
              var active = -1;
              for (var i = 0; i < _lyrics.length; i++) {
                if (_lyrics[i].time <= position) active = i;
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                itemCount: _lyrics.length,
                itemBuilder: (ctx, index) => ListTile(
                  title: Text(_lyrics[index].text, textAlign: TextAlign.center,
                    style: TextStyle(color: active == index ? Colors.white : Colors.white54,
                      fontSize: active == index ? 19 : 15, fontWeight: active == index ? FontWeight.w800 : FontWeight.w500)),
                  onTap: () => _player.seek(_lyrics[index].time + _lyricsOffset),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showAudioOutput() async {
    final devices = _player.state.audioDevices;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Audio output', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              subtitle: Text('Choose an available playback device', style: TextStyle(color: Colors.white54)),
            ),
            for (final device in devices)
              ListTile(
                leading: Icon(
                  _player.state.audioDevice == device ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: _player.state.audioDevice == device ? Colors.white : Colors.white54,
                ),
                title: Text(device.description.isNotEmpty ? device.description : device.name,
                  style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _player.setAudioDevice(device);
                  } catch (_) {
                    _message('Could not switch audio output.');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQueue() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.65,
          child: ListView(
            children: [
              const ListTile(title: Text('Up next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              for (var i = 0; i < _persistent.queue.length; i++)
                ListTile(
                  leading: Icon(i == _persistent.currentIndex ? Icons.equalizer_rounded : Icons.music_note_rounded, color: i == _persistent.currentIndex ? Colors.white : Colors.white54),
                  title: Text(_persistent.queue[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(_persistent.queue[i].path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38)),
                  onTap: () { Navigator.pop(ctx); _player.jump(i); },
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
      onAction: (action) => unawaited(_runOption(action)),
      isFavorite: _favorite,
      isPinned: _pinnedCurrent,
      isCached: _cached,
    );
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 30);
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  String get _artist {
    final parts = _title.split(' - ');
    if (parts.length > 1) return parts.first.trim();
    return _folderName;
  }

  String get _displayTitle {
    final parts = _title.split(' - ');
    return parts.length > 1 ? parts.skip(1).join(' - ').trim() : _title;
  }

  String? _channelLabel(String? channels, int? count) {
    if (count == 1) return 'Mono';
    if (count == 2) return 'Stereo';
    final value = channels?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.toLowerCase().contains('stereo')) return 'Stereo';
    if (value.toLowerCase().contains('mono')) return 'Mono';
    return value;
  }

  String get _audioFormat {
    final audio = _player.state.track.audio;
    final ext = _track.title.contains('.') ? _track.title.split('.').last.toUpperCase() : 'AUDIO';
    final codec = audio.codec?.trim();
    final channels = _channelLabel(audio.channels, audio.channelscount);
    final sampleRate = audio.samplerate;
    return [
      (codec?.isNotEmpty ?? false) ? codec!.toUpperCase() : ext,
      if (sampleRate != null && sampleRate > 0) '${(sampleRate / 1000).toStringAsFixed(1)} kHz',
      if (channels?.isNotEmpty ?? false) channels!,
    ].join('  •  ');
  }

  Widget _artworkSection(double height) => SizedBox(
    height: height,
    width: double.infinity,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (_artwork != null && _artworkKey == _trackKey)
          Image.memory(_artwork!, fit: BoxFit.cover, gaplessPlayback: true)
        else
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF292929), Color(0xFF101010), Colors.black]),
            ),
            child: const Center(child: Icon(Icons.music_note_rounded, size: 104, color: Color(0x33FFFFFF))),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x22000000), Color(0x99000000), Colors.black],
              stops: [0.42, 0.66, 0.86, 1],
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 18,
          right: 18,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
              ),
              Expanded(
                child: Text('PLAYING FROM  •  ${_folderName.toUpperCase()}',
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Track options',
                onPressed: _showOptions,
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 27),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _roundAction(IconData icon, String tooltip, VoidCallback onTap, {bool active = false}) => SizedBox(
    width: 38,
    height: 38,
    child: IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: active ? const Color(0xFFFFD66B) : Colors.white,
      ),
      icon: Icon(icon, size: 19),
    ),
  );

  Widget _transport() => StreamBuilder<bool>(
    stream: _player.stream.playing,
    initialData: _player.state.playing,
    builder: (context, snapshot) {
      final playing = snapshot.data ?? false;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: _persistent.queue.length > 1 ? _player.previous : null,
            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36)),
          IconButton.filled(
            onPressed: _player.playOrPause,
            style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, fixedSize: const Size(68, 68)),
            iconSize: 36,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(onPressed: _persistent.queue.length > 1 ? _player.next : null,
            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36)),
        ],
      );
    },
  );

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
        final current = _dragPosition > 0 ? _dragPosition.clamp(0, max).toDouble() : position.inMilliseconds.toDouble().clamp(0, max).toDouble();
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
                min: 0, max: max, value: current,
                onChangeStart: (value) => setState(() => _dragPosition = value),
                onChanged: (value) => setState(() => _dragPosition = value),
                onChangeEnd: (value) {
                  _player.seek(Duration(milliseconds: value.round()));
                  setState(() => _dragPosition = 0);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_formatDuration(position), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                Text('-${_formatDuration(duration - position)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
          ],
        );
      },
    ),
  );

  Widget _volume() => StreamBuilder<double>(
    stream: _player.stream.volume,
    initialData: _player.state.volume,
    builder: (context, snapshot) => Row(children: [
      const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 18),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: SliderComponentShape.noOverlay),
          child: Slider(min: 0, max: 100, value: (snapshot.data ?? 100).clamp(0, 100).toDouble(),
            activeColor: Colors.white70, inactiveColor: Colors.white12, onChanged: _player.setVolume),
        ),
      ),
      const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 18),
    ]),
  );

  Widget _lyricPreview() => StreamBuilder<Duration>(
    stream: _player.stream.position,
    initialData: _player.state.position,
    builder: (context, snapshot) {
      final position = (snapshot.data ?? Duration.zero) - _lyricsOffset;
      var active = -1;
      for (var i = 0; i < _lyrics.length; i++) {
        if (_lyrics[i].time <= position) active = i;
      }
      final text = active >= 0 ? _lyrics[active].text : (_lyrics.isEmpty ? 'Lyrics  ›' : _lyrics.first.text);
      return InkWell(
        onTap: _showLyrics,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500))),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 17),
          ]),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final artworkHeight = (screenHeight * 0.40).clamp(250.0, 390.0).toDouble();
    final folderLabel = _track.path.contains('/') ? 'Folder / $_folderName' : 'Internal storage';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: true,
        child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                _artworkSection(artworkHeight),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                  child: Column(
                    children: [
                      StreamBuilder<Tracks>(
                        stream: _player.stream.tracks,
                        initialData: _player.state.tracks,
                        builder: (context, snapshot) => Text(_audioFormat,
                          textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 18),
                      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _MarqueeTitle(
                              key: ValueKey(_trackKey),
                              text: _displayTitle,
                              style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                            ),
                            const SizedBox(height: 4),
                            Text(_artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        _roundAction(_favorite ? Icons.star_rounded : Icons.star_border_rounded, 'Favorite', _toggleFavorite, active: _favorite),
                        const SizedBox(width: 8),
                        _roundAction(Icons.more_horiz_rounded, 'More options', _showOptions),
                      ]),
                      const SizedBox(height: 8),
                      _lyricPreview(),
                      const SizedBox(height: 4),
                      _timeline(),
                      const SizedBox(height: 18),
                      _transport(),
                      const SizedBox(height: 12),
                      _volume(),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        IconButton(tooltip: 'Lyrics', onPressed: _showLyrics,
                          icon: const Icon(Icons.lyrics_outlined, color: Colors.white70)),
                        IconButton(tooltip: 'Audio output / Cast', onPressed: _showAudioOutput,
                          icon: const Icon(Icons.speaker_group_outlined, color: Colors.white70)),
                        IconButton(tooltip: 'Queue', onPressed: _showQueue,
                          icon: const Icon(Icons.queue_music_rounded, color: Colors.white70)),
                      ]),
                      Text('PLAYING FROM  $folderLabel', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white30, fontSize: 9, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      StreamBuilder<AudioDevice>(
                        stream: _player.stream.audioDevice,
                        initialData: _player.state.audioDevice,
                        builder: (context, snapshot) {
                          final device = snapshot.data ?? _player.state.audioDevice;
                          final label = device.description.trim().isNotEmpty
                              ? device.description.trim()
                              : device.name == 'auto' ? 'This device' : device.name;
                          return Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11));
                        },
                      ),
                      if (_sleepMinutes != null)
                        Padding(padding: const EdgeInsets.only(top: 6),
                          child: Text('Sleep timer · $_sleepMinutes min', style: const TextStyle(color: Colors.white38, fontSize: 10))),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
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
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12))),
    ]),
  );
}


class _MarqueeTitle extends StatefulWidget {
  const _MarqueeTitle({required this.text, required this.style, super.key});
  final String text;
  final TextStyle style;

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runMarquee());
  }

  Future<void> _runMarquee() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || !_controller.hasClients) return;
      final end = _controller.position.maxScrollExtent;
      if (end <= 0) return;
      await _controller.animateTo(end, duration: Duration(milliseconds: (end * 18).round().clamp(1800, 6000).toInt()), curve: Curves.linear);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      await _controller.animateTo(0, duration: Duration(milliseconds: (end * 18).round().clamp(1800, 6000)), curve: Curves.linear);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
