import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import 'media_player_screen.dart';

enum MediaLibraryType { music, video }

class MediaBrowserScreen extends StatefulWidget {
  const MediaBrowserScreen({
    required this.api,
    required this.type,
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}

class _MediaBrowserScreenState extends State<MediaBrowserScreen> {
  static const _audioExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus',
    'wma', 'aiff', 'alac',
  };
  static const _videoExtensions = {
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv',
    'mpeg', 'mpg', '3gp', 'ts',
  };

  String _path = '';
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;

  bool get _isMusic => widget.type == MediaLibraryType.music;
  String get _title => _isMusic ? 'Music' : 'Videos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? path]) async {
    final target = path ?? _path;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.api.listDirectory(target);
      if (!mounted) return;
      setState(() {
        _path = listing.path == '.' ? '' : listing.path;
        _listing = listing;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _error = status == 401
            ? 'Login expired or credentials are incorrect.'
            : status == 403
                ? 'Access denied.'
                : status == 404
                    ? 'Folder not found.'
                    : error.message ?? 'Could not load media.';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this folder.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isMedia(FileEntry item) {
    final extension = item.name.contains('.')
        ? item.name.split('.').last.toLowerCase()
        : '';
    return (_isMusic ? _audioExtensions : _videoExtensions)
        .contains(extension);
  }

  String _itemPath(String name) => _path.isEmpty ? name : '$_path/$name';

  Future<void> _openMedia(FileEntry item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          title: item.name,
          path: _itemPath(item.name),
          isVideo: !_isMusic,
        ),
      ),
    );
  }

  Future<void> _goUp() async {
    if (_path.isEmpty) return;
    final parts = _path.split('/');
    parts.removeLast();
    await _load(parts.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final items = _listing?.items ?? const <FileEntry>[];
    final folders = items.where((item) => item.isDirectory).toList();
    final media = items.where(_isMedia).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: IconButton(
              tooltip: 'Go up',
              onPressed: _path.isEmpty ? null : _goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            title: Text(_path.isEmpty ? 'All storage' : _path),
            subtitle: Text(_isMusic
                ? 'Browse folders and play audio'
                : 'Browse folders and play videos'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _error != null
                ? Center(
                    child: FilledButton(
                      onPressed: () => _load(),
                      child: const Text('Retry'),
                    ),
                  )
                : _loading && _listing == null
                    ? const SizedBox.shrink()
                    : folders.isEmpty && media.isEmpty
                        ? Center(
                            child: Text(
                              _path.isEmpty
                                  ? 'No ${_title.toLowerCase()} found in storage.'
                                  : 'No ${_title.toLowerCase()} in this folder.',
                            ),
                          )
                        : ListView(
                            children: [
                              for (final folder in folders)
                                ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(folder.name),
                                  subtitle: const Text('Folder'),
                                  onTap: () => _load(_itemPath(folder.name)),
                                ),
                              for (final item in media)
                                ListTile(
                                  leading: Icon(_isMusic
                                      ? Icons.audio_file
                                      : Icons.play_circle_outline),
                                  title: Text(item.name),
                                  subtitle: Text(
                                    '${(item.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  ),
                                  trailing: const Icon(Icons.play_arrow),
                                  onTap: () => _openMedia(item),
                                ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
