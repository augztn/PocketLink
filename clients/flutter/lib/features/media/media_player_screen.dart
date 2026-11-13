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
    required this.isVideo,
    super.key,
  });

  final ServerApi api;
  final String title;
  final String path;
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
          widget.api.mediaStreamUrl(widget.path),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.isVideo)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(
                  controller: _videoController,
                  controls: NoVideoControls,
                ),
              )
            else
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.music_note, size: 88),
              ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (_openError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Playback failed: $_openError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            StreamBuilder<String>(
              stream: _player.stream.error,
              initialData: '',
              builder: (context, snapshot) {
                final error = snapshot.data ?? '';
                if (error.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                );
              },
            ),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              initialData: _player.state.buffering,
              builder: (context, snapshot) => snapshot.data == true
                  ? const LinearProgressIndicator()
                  : const SizedBox(height: 4),
            ),
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
                    final maximum = duration.inMilliseconds
                        .toDouble()
                        .clamp(1, double.infinity)
                        .toDouble();
                    final current = position.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble();
                    return Column(
                      children: [
                        Slider(
                          min: 0,
                          max: maximum,
                          value: current.clamp(0, maximum).toDouble(),
                          onChanged: duration > Duration.zero
                              ? (value) => _player.seek(
                                    Duration(milliseconds: value.round()),
                                  )
                              : null,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position)),
                            Text(_formatDuration(duration)),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: _player.state.playing,
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Center(
                  child: IconButton.filled(
                    iconSize: 34,
                    onPressed: _player.playOrPause,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: StreamBuilder<double>(
                    stream: _player.stream.volume,
                    initialData: _player.state.volume,
                    builder: (context, snapshot) {
                      final volume = (snapshot.data ?? 100)
                          .clamp(0, 100)
                          .toDouble();
                      return Slider(
                        min: 0,
                        max: 100,
                        value: volume,
                        onChanged: _player.setVolume,
                      );
                    },
                  ),
                ),
                const Icon(Icons.volume_up),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
