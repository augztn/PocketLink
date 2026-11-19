import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../../core/widgets/pocketlink_app_bar.dart';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../settings/video_player_settings_screen.dart';
import 'persistent_audio_player.dart';

class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    required this.api,
    required this.title,
    required this.path,
    this.volume,
    required this.isVideo,
    this.queue = const [],
    this.initialIndex = 0,
    this.resumeExisting = false,
    super.key,
  });

  final ServerApi api;
  final String title;
  final String path;
  final String? volume;
  final bool isVideo;
  final List<MediaQueueItem> queue;
  final int initialIndex;
  final bool resumeExisting;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final PersistentAudioPlayer _persistent;
  late final Player _player;
  String? _openError;
  int _currentIndex = 0;
  bool _shuffle = false;
  PlaylistMode _repeatMode = PlaylistMode.none;
  double _playbackRate = 1;
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  Timer? _sleepTimer;
  Timer? _videoControlsTimer;
  bool _showVideoControls = true;
  bool _isVideoFullscreen = false;
  Uint8List? _coverBytes;
  String? _coverForTrack;
  int _artworkRequestId = 0;
  double? _gestureStartVolume;
  double? _gestureStartBrightness;
  double? _gestureStartY;
  String? _gestureMode;
  double? _gestureValue;
  static const MethodChannel _videoControlChannel = MethodChannel('pocketlink/media');
  final TransformationController _videoTransformController = TransformationController();

  List<MediaQueueItem> get _queue => widget.queue.isEmpty
      ? [MediaQueueItem(title: widget.title, path: widget.path, volume: widget.volume)]
      : widget.queue;

  @override
  void initState() {
    super.initState();
    _persistent = PersistentAudioPlayer.instance;
    _player = _persistent.player;
    _currentIndex = widget.resumeExisting
        ? _persistent.currentIndex
        : widget.initialIndex.clamp(0, _queue.length - 1).toInt();
    if (widget.isVideo) _playbackRate = AppSettings.instance.videoDefaultSpeed;
    _playlistSubscription = _player.stream.playlist.listen((playlist) {
      if (mounted && _queue.isNotEmpty) {
        final index = playlist.index.clamp(0, _queue.length - 1).toInt();
        setState(() {
          _currentIndex = index;
          _coverBytes = null;
          _coverForTrack = null;
          _videoTransformController.value = _videoTransformController.value.clone()..setIdentity();
        });
        unawaited(_loadArtwork(_queue[index]));
      }
    });
    _tracksSubscription = _player.stream.tracks.listen((_) {
      if (mounted) setState(() {});
    });
    _trackSubscription = _player.stream.track.listen((_) {
      if (mounted) setState(() {});
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        _scheduleVideoControlsHide();
      } else if (mounted && widget.isVideo) {
        _videoControlsTimer?.cancel();
        if (!_showVideoControls) setState(() => _showVideoControls = true);
      }
    });
    unawaited(_loadArtwork(_queue[_currentIndex]));
    if (!widget.resumeExisting) _open();
  }

  Future<void> _open() async {
    try {
      await _persistent.openQueue(
        api: widget.api,
        queue: _queue,
        initialIndex: _currentIndex,
        isMusic: !widget.isVideo,
      );
      if (widget.isVideo) {
        await _player.setRate(_playbackRate);
        if (AppSettings.instance.videoAutoFullscreen && mounted) {
          await _toggleVideoFullscreen();
        }
      }
    } catch (error) {
      if (mounted) setState(() => _openError = error.toString());
    }
  }

  Future<void> _toggleShuffle() async {
    final value = !_shuffle;
    await _player.setShuffle(value);
    if (mounted) setState(() => _shuffle = value);
  }

  Future<void> _cycleRepeat() async {
    final value = switch (_repeatMode) {
      PlaylistMode.none => PlaylistMode.loop,
      PlaylistMode.loop => PlaylistMode.single,
      PlaylistMode.single => PlaylistMode.none,
    };
    await _player.setPlaylistMode(value);
    if (mounted) setState(() => _repeatMode = value);
  }

  Future<void> _setPlaybackRate(double value) async {
    await _player.setRate(value);
    if (widget.isVideo) {
      await AppSettings.instance.setVideoPlayerOptions(defaultSpeed: value);
    }
    if (mounted) setState(() => _playbackRate = value);
  }

  String _trackLabel({required String? title, required String? language, required String? codec, required String id, required int index}) {
    if (id == 'auto') return 'Auto select';
    if (id == 'no') return 'Off';
    final parts = <String>[
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (language != null && language.trim().isNotEmpty && language != title) language.trim().toUpperCase(),
      if (codec != null && codec.trim().isNotEmpty) codec.trim().toUpperCase(),
    ];
    return parts.isEmpty ? 'Track ${index + 1}' : parts.join(' · ');
  }

  Future<void> _showAudioTracks() async {
    final tracks = _player.state.tracks.audio;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171421),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Audio track', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            for (var index = 0; index < tracks.length; index++)
              ListTile(
                leading: Icon(_player.state.track.audio.id == tracks[index].id ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFFD8C9FF)),
                title: Text(_trackLabel(title: tracks[index].title, language: tracks[index].language, codec: tracks[index].codec, id: tracks[index].id, index: index), style: const TextStyle(color: Colors.white)),
                subtitle: tracks[index].channels == null ? null : Text(tracks[index].channels!, style: const TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_player.setAudioTrack(tracks[index]));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadExternalSubtitleFromServer() async {
    final track = _queue[_currentIndex.clamp(0, _queue.length - 1).toInt()];
    final extensionIndex = track.path.lastIndexOf('.');
    final slashIndex = track.path.lastIndexOf('/');
    final withoutExtension = extensionIndex > slashIndex
        ? track.path.substring(0, extensionIndex)
        : track.path;
    for (final extension in const ['srt', 'ass', 'ssa', 'vtt']) {
      final subtitlePath = '$withoutExtension.$extension';
      try {
        final bytes = track.volume == null
            ? await widget.api.downloadFile(subtitlePath)
            : await widget.api.downloadStorageFile(track.volume!, subtitlePath);
        if (bytes.isEmpty) continue;
        final data = utf8.decode(bytes, allowMalformed: true);
        await _player.setSubtitleTrack(SubtitleTrack.data(data, title: subtitlePath.split('/').last));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded ${subtitlePath.split('/').last}')),
          );
        }
        return;
      } catch (_) {
        // Try the next supported sidecar extension.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching .srt, .ass, .ssa or .vtt file found beside this video.')),
      );
    }
  }

  Future<void> _pickExternalSubtitle() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('Could not read the selected subtitle file.');
      }
      final data = utf8.decode(bytes, allowMalformed: true);
      await _player.setSubtitleTrack(SubtitleTrack.data(data, title: file.name));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${file.name}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load subtitle: $error')),
        );
      }
    }
  }


  Future<void> _pickExternalAudio() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['aac', 'ac3', 'flac', 'm4a', 'mka', 'mp3', 'ogg', 'opus', 'wav'],
      );
      if (file == null) return;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected audio file has no readable local path.');
      }
      await _player.setAudioTrack(
        AudioTrack.uri(Uri.file(path).toString(), title: file.name),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded audio: ${file.name}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load external audio: $error')),
        );
      }
    }
  }

  Future<void> _openVideoSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const VideoPlayerSettingsScreen()),
    );
    if (!mounted) return;
    if (!AppSettings.instance.videoPinchZoomEnabled) {
      _videoTransformController.value = _videoTransformController.value.clone()..setIdentity();
    }
    setState(() {});
    _revealVideoControls();
  }

  Future<void> _showSubtitleTracks() async {
    final tracks = _player.state.tracks.subtitle;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171421),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Subtitles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            ListTile(
              leading: Icon(_player.state.track.subtitle.id == 'no' ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFFD8C9FF)),
              title: const Text('Off', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
              },
            ),
            ListTile(
              leading: Icon(_player.state.track.subtitle.id == 'auto' ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFFD8C9FF)),
              title: const Text('Auto select', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_player.setSubtitleTrack(SubtitleTrack.auto()));
              },
            ),
            for (var index = 0; index < tracks.length; index++)
              if (tracks[index].id != 'auto' && tracks[index].id != 'no')
                ListTile(
                  leading: Icon(_player.state.track.subtitle.id == tracks[index].id ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFFD8C9FF)),
                  title: Text(_trackLabel(title: tracks[index].title, language: tracks[index].language, codec: tracks[index].codec, id: tracks[index].id, index: index), style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_player.setSubtitleTrack(tracks[index]));
                  },
                ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.white70),
              title: const Text('Load matching subtitle from server', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_loadExternalSubtitleFromServer());
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined, color: Colors.white70),
              title: const Text('Choose subtitle file', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_pickExternalSubtitle());
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
      showDragHandle: true,
      backgroundColor: const Color(0xFF171421),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(widget.isVideo ? 'VIDEO QUEUE' : 'UP NEXT', style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              )),
            ),
            for (var index = 0; index < _queue.length; index++)
              ListTile(
                leading: Icon(
                  index == _currentIndex
                      ? Icons.equalizer_rounded
                      : widget.isVideo
                          ? Icons.movie_outlined
                          : Icons.music_note_rounded,
                  color: index == _currentIndex ? const Color(0xFFD8C9FF) : Colors.white54,
                ),
                title: Text(_queue[index].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white)),
                subtitle: Text(_queue[index].path,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38)),
                onTap: () {
                  Navigator.pop(context);
                  _player.jump(index);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseSleepTimer() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Sleep timer')),
            for (final value in [15, 30, 45, 60])
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(value.toString() + ' minutes'),
                onTap: () => Navigator.pop(context, value),
              ),
            if (_sleepTimer != null)
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('Cancel timer'),
                onTap: () => Navigator.pop(context, 0),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    _sleepTimer?.cancel();
    if (minutes == 0) {
      if (mounted) setState(() {});
      return;
    }
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _player.pause();
      _sleepTimer = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sleep timer paused playback.')),
        );
        setState(() {});
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _showLyrics() async {
    final track = _queue[_currentIndex.clamp(0, _queue.length - 1).toInt()];
    final withoutExtension = track.path.replaceAll(RegExp(r'\.[^.]+$'), '');
    final lyricsPath = withoutExtension + '.lrc';
    try {
      final bytes = track.volume == null
          ? await widget.api.downloadFile(lyricsPath)
          : await widget.api.downloadStorageFile(track.volume!, lyricsPath);
      final raw = utf8.decode(bytes, allowMalformed: true);
      final pattern = RegExp(
        r'^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$',
        multiLine: true,
      );
      final lines = pattern.allMatches(raw).map((match) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = (match.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        return (
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: int.parse(fraction),
          ),
          text: match.group(4)!.trim(),
        );
      }).toList()..sort((a, b) => a.time.compareTo(b.time));

      if (!mounted) return;
      if (lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No synchronized lyrics found in the matching .lrc file.')),
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: const Color(0xFF171421),
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.68,
            child: StreamBuilder<Duration>(
              stream: _player.stream.position,
              initialData: _player.state.position,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                var active = -1;
                for (var i = 0; i < lines.length; i++) {
                  if (lines[i].time <= position) active = i;
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  itemCount: lines.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(
                      lines[index].text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: index == active ? Colors.white : Colors.white54,
                        fontSize: index == active ? 19 : 15,
                        fontWeight: index == active ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    onTap: () => _player.seek(lines[index].time),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lyrics not found. Add a matching .lrc file beside the song.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _videoControlsTimer?.cancel();
    _videoTransformController.dispose();
    if (widget.isVideo) unawaited(_restoreVideoBrightness());
    if (_isVideoFullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
    }
    unawaited(_playlistSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_tracksSubscription?.cancel());
    unawaited(_trackSubscription?.cancel());
    unawaited(_persistent.closePlayerScreen(isVideo: widget.isVideo));
    super.dispose();
  }

  void _scheduleVideoControlsHide() {
    _videoControlsTimer?.cancel();
    if (!_player.state.playing || !_showVideoControls || !widget.isVideo) return;
    final timeout = AppSettings.instance.videoControlsTimeoutSeconds;
    if (timeout <= 0) return;
    _videoControlsTimer = Timer(Duration(seconds: timeout), () {
      if (mounted && _player.state.playing) {
        setState(() => _showVideoControls = false);
      }
    });
  }

  void _revealVideoControls() {
    if (!_showVideoControls) setState(() => _showVideoControls = true);
    _scheduleVideoControlsHide();
  }

  Future<void> _seekRelative(Duration offset) async {
    final duration = _player.state.duration;
    final target = _player.state.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && target > duration
            ? duration
            : target;
    await _player.seek(clamped);
    _revealVideoControls();
  }

  Future<void> _toggleVideoFullscreen() async {
    final next = !_isVideoFullscreen;
    setState(() {
      _isVideoFullscreen = next;
      _showVideoControls = true;
    });
    if (next) {
      final orientation = AppSettings.instance.videoFullscreenOrientation;
      await SystemChrome.setPreferredOrientations(switch (orientation) {
        'portrait' => const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
        'auto' => const <DeviceOrientation>[],
        _ => const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      });
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    _scheduleVideoControlsHide();
  }


  double get _videoGestureWidth {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return _isVideoFullscreen
        ? screenWidth
        : (screenWidth - 48).clamp(1, 512).toDouble();
  }

  Future<void> _beginVerticalVideoGesture(DragStartDetails details) async {
    final width = _videoGestureWidth;
    if (details.localPosition.dx < width * 0.45) {
      try {
        final brightness = await _videoControlChannel.invokeMethod<double>('getVideoBrightness') ?? 0.5;
        if (!mounted) return;
        setState(() {
          _gestureStartBrightness = brightness;
          _gestureStartVolume = null;
          _gestureStartY = details.localPosition.dy;
          _gestureMode = 'brightness';
          _gestureValue = brightness;
        });
      } on PlatformException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Brightness gesture is unavailable on this device.')),
          );
        }
      } on MissingPluginException {
        // Non-Android builds do not register the PocketLink native channel.
      }
    } else if (details.localPosition.dx > width * 0.55) {
      setState(() {
        _gestureStartVolume = _player.state.volume;
        _gestureStartBrightness = null;
        _gestureStartY = details.localPosition.dy;
        _gestureMode = 'volume';
        _gestureValue = _player.state.volume;
      });
    }
  }

  void _updateVerticalVideoGesture(DragUpdateDetails details) {
    final startY = _gestureStartY;
    if (startY == null || _gestureMode == null) return;
    final viewport = MediaQuery.sizeOf(context);
    final height = _isVideoFullscreen ? viewport.height : viewport.width * 9 / 16;
    final delta = details.localPosition.dy - startY;
    if (_gestureMode == 'brightness' && _gestureStartBrightness != null) {
      final value = (_gestureStartBrightness! - delta / height).clamp(0.01, 1.0).toDouble();
      _gestureValue = value;
      unawaited(_videoControlChannel.invokeMethod<void>(
        'setVideoBrightness',
        {'brightness': value},
      ));
    } else if (_gestureMode == 'volume' && _gestureStartVolume != null) {
      final value = (_gestureStartVolume! - delta / height * 100).clamp(0, 100).toDouble();
      _gestureValue = value;
      unawaited(_player.setVolume(value));
    }
    if (mounted) setState(() {});
  }

  void _endVerticalVideoGesture() {
    if (!mounted) return;
    setState(() {
      _gestureStartVolume = null;
      _gestureStartBrightness = null;
      _gestureStartY = null;
      _gestureMode = null;
      _gestureValue = null;
    });
    _revealVideoControls();
  }

  Future<void> _restoreVideoBrightness() async {
    try {
      await _videoControlChannel.invokeMethod<void>('restoreVideoBrightness');
    } on PlatformException {
      // The player can still close if Android has already detached the activity.
    } on MissingPluginException {
      // Non-Android builds have no scoped window-brightness override.
    }
  }

  Widget _videoSurface() {
    final surface = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _videoTransformController,
            minScale: 1,
            maxScale: 3,
            scaleEnabled: AppSettings.instance.videoPinchZoomEnabled,
            panEnabled: AppSettings.instance.videoPinchZoomEnabled,
            child: SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(
                    controller: _persistent.videoController,
                    controls: NoVideoControls,
                    fit: switch (AppSettings.instance.videoFitMode) {
                      'cover' => BoxFit.cover,
                      'fill' => BoxFit.fill,
                      _ => BoxFit.contain,
                    },
                    subtitleViewConfiguration: SubtitleViewConfiguration(
                      style: TextStyle(
                        fontSize: AppSettings.instance.videoSubtitleFontSize,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        backgroundColor: AppSettings.instance.videoSubtitleBackground
                            ? const Color(0xAA000000)
                            : Colors.transparent,
                      ),
                      textAlign: TextAlign.center,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (AppSettings.instance.videoTapToTogglePlayback) {
                          unawaited(_player.playOrPause());
                        }
                        _revealVideoControls();
                      },
                      onDoubleTapDown: AppSettings.instance.videoGesturesEnabled
                          ? (details) {
                              final width = _videoGestureWidth;
                              final seconds = AppSettings.instance.videoSeekSeconds;
                              _seekRelative(Duration(
                                seconds: details.localPosition.dx < width / 2 ? -seconds : seconds,
                              ));
                            }
                          : null,
                      onVerticalDragStart: AppSettings.instance.videoGesturesEnabled
                          ? _beginVerticalVideoGesture
                          : null,
                      onVerticalDragUpdate: AppSettings.instance.videoGesturesEnabled
                          ? _updateVerticalVideoGesture
                          : null,
                      onVerticalDragEnd: (_) => _endVerticalVideoGesture(),
                      onHorizontalDragEnd: AppSettings.instance.videoGesturesEnabled
                          ? (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity.abs() < 250) return;
                              final seconds = AppSettings.instance.videoSeekSeconds *
                                  (velocity.abs() / 1000).clamp(1, 4).round();
                              _seekRelative(Duration(seconds: velocity > 0 ? seconds : -seconds));
                            }
                          : null,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_gestureMode != null && _gestureValue != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _gestureMode == 'brightness'
                              ? Icons.brightness_6_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 112,
                          child: LinearProgressIndicator(
                            value: _gestureMode == 'brightness'
                                ? _gestureValue!.clamp(0, 1)
                                : _gestureValue!.clamp(0, 100) / 100,
                            backgroundColor: Colors.white24,
                            color: const Color(0xFFD8C9FF),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _gestureMode == 'brightness'
                              ? '${(_gestureValue! * 100).round()}%'
                              : '${_gestureValue!.round()}%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showVideoControls)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.68),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    stops: const [0, 0.28, 0.58, 1],
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () {
                            if (_isVideoFullscreen) {
                              _toggleVideoFullscreen();
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        Expanded(
                          child: Text(
                            _queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].title
                                .replaceAll(RegExp(r'\.[^.]+$'), ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Video queue',
                          onPressed: _showQueue,
                          icon: const Icon(Icons.queue_play_next_rounded, color: Colors.white),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Video options',
                          color: const Color(0xFF24202E),
                          onSelected: (value) {
                            if (value == 'audio') {
                              unawaited(_showAudioTracks());
                            } else if (value == 'subtitles') {
                              unawaited(_showSubtitleTracks());
                            } else if (value == 'externalAudio') {
                              unawaited(_pickExternalAudio());
                            } else {
                              unawaited(_openVideoSettings());
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'audio',
                              child: Row(children: [
                                Icon(Icons.audiotrack_rounded, color: Colors.white70),
                                SizedBox(width: 12),
                                Text('Audio tracks', style: TextStyle(color: Colors.white)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'subtitles',
                              child: Row(children: [
                                Icon(Icons.closed_caption_rounded, color: Colors.white70),
                                SizedBox(width: 12),
                                Text('Subtitles', style: TextStyle(color: Colors.white)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'externalAudio',
                              child: Row(children: [
                                Icon(Icons.audiotrack_rounded, color: Colors.white70),
                                SizedBox(width: 12),
                                Text('Load external audio', style: TextStyle(color: Colors.white)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'settings',
                              child: Row(children: [
                                Icon(Icons.video_settings_rounded, color: Colors.white70),
                                SizedBox(width: 12),
                                Text('Video player settings', style: TextStyle(color: Colors.white)),
                              ]),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.tune_rounded, color: Colors.white),
                          ),
                        ),
                        PopupMenuButton<double>(
                          tooltip: 'Playback speed',
                          initialValue: _playbackRate,
                          color: const Color(0xFF24202E),
                          onSelected: _setPlaybackRate,
                          itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0]
                              .map((rate) => PopupMenuItem(
                                    value: rate,
                                    child: Text(
                                      '${rate}×',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ))
                              .toList(),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '${_playbackRate}×',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _isVideoFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                          onPressed: _toggleVideoFullscreen,
                          icon: Icon(
                            _isVideoFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    StreamBuilder<bool>(
                      stream: _player.stream.playing,
                      initialData: _player.state.playing,
                      builder: (context, snapshot) {
                        final playing = snapshot.data ?? false;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous video',
                              onPressed: _queue.length > 1 ? _player.previous : null,
                              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 32),
                            ),
                            IconButton(
                              tooltip: 'Back 10 seconds',
                              onPressed: () => _seekRelative(Duration(seconds: -AppSettings.instance.videoSeekSeconds)),
                              icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 38),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filled(
                              tooltip: playing ? 'Pause' : 'Play',
                              onPressed: () async {
                                await _player.playOrPause();
                                _revealVideoControls();
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                fixedSize: const Size(68, 68),
                              ),
                              iconSize: 36,
                              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Forward 10 seconds',
                              onPressed: () => _seekRelative(Duration(seconds: AppSettings.instance.videoSeekSeconds)),
                              icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 38),
                            ),
                            IconButton(
                              tooltip: 'Next video',
                              onPressed: _queue.length > 1 ? _player.next : null,
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 32),
                            ),
                          ],
                        );
                      },
                    ),
                    const Spacer(),
                    StreamBuilder<Duration>(
                      stream: _player.stream.position,
                      initialData: _player.state.position,
                      builder: (context, positionSnapshot) {
                        final position = positionSnapshot.data ?? Duration.zero;
                        return StreamBuilder<Duration>(
                          stream: _player.stream.duration,
                          initialData: _player.state.duration,
                          builder: (context, durationSnapshot) {
                            final duration = durationSnapshot.data ?? Duration.zero;
                            final maximum = duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
                            final current = position.inMilliseconds.toDouble().clamp(0, maximum).toDouble();
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      activeTrackColor: const Color(0xFFD8C9FF),
                                      inactiveTrackColor: Colors.white38,
                                      thumbColor: Colors.white,
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: maximum,
                                      value: current,
                                      onChanged: duration > Duration.zero
                                          ? (value) => _player.seek(Duration(milliseconds: value.round()))
                                          : null,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                      Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (_isVideoFullscreen) return SizedBox.expand(child: surface);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(aspectRatio: 16 / 9, child: surface),
    );
  }

  String _formatDuration(Duration value) {
    String two(int number) => number.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return hours > 0
        ? '$hours:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
  }

  Future<void> _loadArtwork(MediaQueueItem track) async {
    final requestId = ++_artworkRequestId;
    final trackKey = '${track.volume ?? 'internal'}:${track.path}';
    final folder = track.path.contains('/')
        ? track.path.substring(0, track.path.lastIndexOf('/') + 1)
        : '';

    // Inspect the folder once instead of issuing a series of expected 404s.
    try {
      final listing = track.volume == null
          ? await widget.api.listDirectory(folder)
          : await widget.api.listStorageDirectory(track.volume!, folder);
      if (requestId != _artworkRequestId || !mounted) return;

      const preferredNames = [
        'cover.jpg', 'cover.jpeg', 'cover.png', 'cover.webp',
        'folder.jpg', 'folder.png', 'album.jpg', 'album.png', 'front.jpg',
      ];
      FileEntry? artwork;
      for (final name in preferredNames) {
        for (final item in listing.items) {
          if (!item.isDirectory && item.name.toLowerCase() == name) {
            artwork = item;
            break;
          }
        }
        if (artwork != null) break;
      }

      if (artwork != null) {
        final path = '$folder${artwork.name}';
        final bytes = track.volume == null
            ? await widget.api.downloadFile(path)
            : await widget.api.downloadStorageFile(track.volume!, path);
        if (requestId != _artworkRequestId || !mounted) return;
        if (bytes.isNotEmpty) {
          setState(() {
            _coverBytes = bytes;
            _coverForTrack = trackKey;
          });
          return;
        }
      }
    } catch (_) {
      // Artwork is optional; keep playback working when it is unavailable.
    }

    if (requestId == _artworkRequestId && mounted) {
      setState(() {
        _coverBytes = null;
        _coverForTrack = trackKey;
      });
    }
  }
  Widget _artwork() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8064D8), Color(0xFF392A68), Color(0xFF15172D)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8064D8).withValues(alpha: 0.28),
              blurRadius: 42,
              spreadRadius: 2,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (_coverBytes != null && _coverForTrack == '${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].volume ?? 'internal'}:${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].path}')
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.memory(
                  _coverBytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (_coverBytes == null || _coverForTrack != '${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].volume ?? 'internal'}:${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].path}')
              Positioned(
              top: -42,
              right: -28,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.5),
                ),
              ),
            ),
            Positioned(
              bottom: -72,
              left: -52,
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.5),
                ),
              ),
            ),
            if (_coverBytes == null || _coverForTrack != '${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].volume ?? 'internal'}:${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].path}')
              Container(
              width: 174,
              height: 174,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final size in [142.0, 108.0, 74.0])
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
                      ),
                    ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE8DFFF),
                    ),
                    child: const Icon(Icons.music_note_rounded, size: 32, color: Color(0xFF493779)),
                  ),
                ],
              ),
            ),
            if (_coverBytes == null || _coverForTrack != '${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].volume ?? 'internal'}:${_queue[_currentIndex.clamp(0, _queue.length - 1).toInt()].path}')
              Positioned(
              left: 22,
              bottom: 20,
              child: Text(
                'HOMESERVER • AUDIO',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 10,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playbackControls() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous track',
              onPressed: _queue.length > 1 ? _player.previous : null,
              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 34),
            ),
            IconButton.filled(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: _player.playOrPause,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF2EEFF),
                foregroundColor: const Color(0xFF21183A),
                fixedSize: const Size(76, 76),
              ),
              iconSize: 38,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: 'Next track',
              onPressed: _queue.length > 1 ? _player.next : null,
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 34),
            ),
          ],
        );
      },
    );
  }

  Widget _timeline() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _player.stream.duration,
          initialData: _player.state.duration,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final maximum = duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
            final current = position.inMilliseconds.toDouble().clamp(0, maximum).toDouble();
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: const Color(0xFFD8C9FF),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                    thumbColor: const Color(0xFFF4F0FF),
                  ),
                  child: Slider(
                    min: 0,
                    max: maximum,
                    value: current,
                    onChanged: duration > Duration.zero
                        ? (value) => _player.seek(Duration(milliseconds: value.round()))
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      Text(_formatDuration(duration), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _volumeControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_down_rounded, color: Colors.white70, size: 20),
          Expanded(
            child: StreamBuilder<double>(
              stream: _player.stream.volume,
              initialData: _player.state.volume,
              builder: (context, snapshot) {
                final volume = (snapshot.data ?? 100).clamp(0, 100).toDouble();
                return Slider(
                  min: 0,
                  max: 100,
                  value: volume,
                  activeColor: const Color(0xFFD8C9FF),
                  inactiveColor: Colors.white24,
                  onChanged: _player.setVolume,
                );
              },
            ),
          ),
          const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = _queue[_currentIndex.clamp(0, _queue.length - 1).toInt()];
    final title = currentTrack.title.replaceAll(RegExp(r'\.[^.]+$'), '');
    final folder = currentTrack.path.split('/').take(currentTrack.path.split('/').length - 1).join('/');
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A12),
      appBar: widget.isVideo && _isVideoFullscreen
          ? null
          : PocketLinkAppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.isVideo ? 'NOW PLAYING' : 'HOMESERVER MUSIC',
          style: const TextStyle(fontSize: 11, letterSpacing: 2.0, fontWeight: FontWeight.w700),
        ),
      ),
      body: widget.isVideo && _isVideoFullscreen
          ? _videoSurface()
          : Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF211A35), Color(0xFF100F19), Color(0xFF09090E)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                children: [
                  if (widget.isVideo)
                    _videoSurface()
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _artwork(),
                    ),
                  const SizedBox(height: 30),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 23, height: 1.2, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isVideo ? 'Streaming from your PocketLink' : 'Your personal music library',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  if (_openError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('Playback failed: $_openError', textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF8A8A))),
                    ),
                  StreamBuilder<String>(
                    stream: _player.stream.error,
                    initialData: '',
                    builder: (context, snapshot) {
                      final error = snapshot.data ?? '';
                      if (error.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error, textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFFF8A8A))),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  StreamBuilder<bool>(
                    stream: _player.stream.buffering,
                    initialData: _player.state.buffering,
                    builder: (context, snapshot) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: snapshot.data == true
                          ? const LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.white12,
                              color: Color(0xFFD8C9FF),
                            )
                          : const SizedBox(height: 2),
                    ),
                  ),
                  _timeline(),
                  const SizedBox(height: 16),
                  _playbackControls(),
                  if (!widget.isVideo) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          tooltip: 'Shuffle',
                          onPressed: _toggleShuffle,
                          color: _shuffle ? const Color(0xFFD8C9FF) : Colors.white54,
                          icon: const Icon(Icons.shuffle_rounded),
                        ),
                        IconButton(
                          tooltip: 'Repeat',
                          onPressed: _cycleRepeat,
                          color: _repeatMode == PlaylistMode.none ? Colors.white54 : const Color(0xFFD8C9FF),
                          icon: Icon(_repeatMode == PlaylistMode.single
                              ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                        ),
                        IconButton(
                          tooltip: 'Lyrics',
                          onPressed: _showLyrics,
                          color: Colors.white70,
                          icon: const Icon(Icons.lyrics_outlined),
                        ),
                        IconButton(
                          tooltip: 'Sleep timer',
                          onPressed: _chooseSleepTimer,
                          color: _sleepTimer == null ? Colors.white70 : const Color(0xFFD8C9FF),
                          icon: const Icon(Icons.bedtime_outlined),
                        ),
                        IconButton(
                          tooltip: 'Up next',
                          onPressed: _showQueue,
                          color: Colors.white70,
                          icon: const Icon(Icons.queue_music_rounded),
                        ),
                        PopupMenuButton<double>(
                          tooltip: 'Playback speed',
                          initialValue: _playbackRate,
                          onSelected: _setPlaybackRate,
                          itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                              .map((rate) => PopupMenuItem(
                                value: rate,
                                child: Text(rate.toString() + '×'),
                              )).toList(),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_playbackRate.toString() + '×',
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 28),
                  _volumeControl(),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_done_outlined, size: 15, color: Colors.white38),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'SECURE STREAM • $folder',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
