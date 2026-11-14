import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/network/server_api.dart';

class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    required this.api,
    required this.title,
    required this.path,
    this.volume,
    required this.isVideo,
    super.key,
  });

  final ServerApi api;
  final String title;
  final String path;
  final String? volume;
  final bool isVideo;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(
        Media(
          widget.api.mediaStreamUrl(widget.path, volume: widget.volume),
          httpHeaders: widget.api.mediaHeaders,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _openError = error.toString());
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
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
              color: const Color(0xFF8064D8).withOpacity(0.28),
              blurRadius: 42,
              spreadRadius: 2,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: -42,
              right: -28,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.10), width: 1.5),
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
                  border: Border.all(color: Colors.white.withOpacity(0.10), width: 1.5),
                ),
              ),
            ),
            Container(
              width: 174,
              height: 174,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.18),
                border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
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
                        border: Border.all(color: Colors.white.withOpacity(0.13)),
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
            Positioned(
              left: 22,
              bottom: 20,
              child: Text(
                'HOMESERVER • AUDIO',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
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
            const SizedBox(width: 56),
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
            const SizedBox(width: 56),
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
                    inactiveTrackColor: Colors.white.withOpacity(0.16),
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
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
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
    final title = widget.title.replaceAll(RegExp(r'\.[^.]+$'), '');
    final folder = widget.path.split('/').take(widget.path.split('/').length - 1).join('/');
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.isVideo ? 'NOW PLAYING' : 'HOMESERVER MUSIC',
          style: const TextStyle(fontSize: 11, letterSpacing: 2.0, fontWeight: FontWeight.w700),
        ),
      ),
      body: Container(
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Video(controller: _videoController, controls: NoVideoControls),
                      ),
                    )
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
                    widget.isVideo ? 'Streaming from your HomeServer' : 'Your personal music library',
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
