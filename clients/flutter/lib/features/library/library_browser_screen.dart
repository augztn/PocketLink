import 'package:dio/dio.dart';
import '../../core/widgets/home_server_app_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';

enum LibraryCategory { images, documents }

class LibraryBrowserScreen extends StatefulWidget {
  const LibraryBrowserScreen({
    required this.api,
    required this.category,
    super.key,
  });

  final ServerApi api;
  final LibraryCategory category;

  @override
  State<LibraryBrowserScreen> createState() => _LibraryBrowserScreenState();
}

class _LibraryBrowserScreenState extends State<LibraryBrowserScreen> {
  static const _imageExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp',
  };
  static const _documentExtensions = {
    'pdf', 'doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'csv',
    'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp',
  };
  static const _maxDirectories = 2000;
  static const _maxDepth = 20;

  final _searchController = TextEditingController();
  List<({FileEntry entry, String path})> _files = const [];
  bool _loading = true;
  String? _error;
  int _scanned = 0;
  int _skipped = 0;

  bool get _isImages => widget.category == LibraryCategory.images;
  String get _title => _isImages ? 'Images' : 'Documents';
  List<String> get _roots => _isImages
      ? const ['Pictures', 'DCIM', 'Download']
      : const ['Documents', 'Download'];

  List<({FileEntry entry, String path})> get _visibleFiles {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _files;
    return _files.where((file) =>
      file.entry.name.toLowerCase().contains(query) ||
      file.path.toLowerCase().contains(query)
    ).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(FileEntry file) {
    final dot = file.name.lastIndexOf('.');
    if (dot < 0) return false;
    final extension = file.name.substring(dot + 1).toLowerCase();
    return (_isImages ? _imageExtensions : _documentExtensions)
        .contains(extension);
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _files = const [];
      _scanned = 0;
      _skipped = 0;
    });

    final found = <({FileEntry entry, String path})>[];
    final visited = <String>{};
    final pending = <({String path, int depth})>[
      for (final root in _roots) (path: root, depth: 0),
    ];

    try {
      while (pending.isNotEmpty && visited.length < _maxDirectories) {
        final current = pending.removeLast();
        if (!visited.add(current.path)) continue;

        DirectoryListing listing;
        try {
          listing = await widget.api.listDirectory(current.path);
          _scanned++;
        } on DioException catch (error) {
          if (error.response?.statusCode == 404) continue;
          if (error.response?.statusCode == 403) {
            _skipped++;
            continue;
          }
          rethrow;
        }

        for (final item in listing.items) {
          final path = '${current.path}/${item.name}';
          if (item.isDirectory) {
            if (current.depth < _maxDepth) {
              pending.add((path: path, depth: current.depth + 1));
            } else {
              _skipped++;
            }
          } else if (_matches(item)) {
            found.add((entry: item, path: path));
          }
        }
        if (mounted) setState(() => _files = List.unmodifiable(found));
      }

      if (pending.isNotEmpty) _skipped++;
      found.sort((a, b) =>
          a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() => _error = status == 401
          ? 'Login expired or credentials are incorrect.'
          : error.message ?? 'Could not scan $_title folders.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not scan $_title folders.');
    } finally {
      if (mounted) {
        setState(() {
          _files = List.unmodifiable(found);
          _loading = false;
        });
      }
    }
  }

  Future<void> _openImage(({FileEntry entry, String path}) file) async {
    if (file.entry.size > 20 * 1024 * 1024) {
      _message('Image preview is limited to 20 MB. Download it instead.');
      return;
    }
    try {
      final bytes = await widget.api.downloadFile(file.path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: Text(file.entry.name)),
            body: Center(
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Text('This image format could not be previewed.'),
                ),
              ),
            ),
          ),
        ),
      );
    } on DioException catch (error) {
      _message(error.response?.statusCode == 401
          ? 'Login expired or credentials are incorrect.'
          : error.message ?? 'Could not load image.');
    } catch (_) {
      _message('Could not preview this image.');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _download(({FileEntry entry, String path}) file) async {
    try {
      final bytes = await widget.api.downloadFile(file.path);
      if (!mounted) return;
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${file.entry.name}',
        fileName: file.entry.name,
        bytes: bytes,
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $saved')),
        );
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 401
            ? 'Login expired or credentials are incorrect.'
            : error.message ?? 'Could not download file.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this file.')),
        );
      }
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(1)} ${units[index]}';
  }

  @override
  Widget build(BuildContext context) {
    final files = _visibleFiles;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: HomeServerAppBar(
        title: Text(_title),
        actions: [
          HomeServerAppBarAction(label: 'Scan again', icon: Icons.refresh, onPressed: _loading ? null : _scan),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search $_title',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          ListTile(
            dense: true,
            leading: Icon(_isImages ? Icons.photo_library : Icons.folder_copy),
            title: Text(_roots.join('  ·  ')),
            subtitle: Text(_loading
                ? 'Scanning folders…'
                : '${_files.length} files  ·  $_scanned folders scanned'
                  '${_skipped > 0 ? '  ·  $_skipped skipped' : ''}'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
          Expanded(
            child: _error != null
                ? Center(child: FilledButton(
                    onPressed: _scan, child: const Text('Retry scan')))
                : _loading && _files.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : files.isEmpty
                        ? Center(child: Text(
                            _searchController.text.isEmpty
                                ? 'No ${_title.toLowerCase()} found in ${_roots.join(', ')}.'
                                : 'No matching files found.',
                            textAlign: TextAlign.center,
                          ))
                        : ListView.separated(
                            itemCount: files.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 72),
                            itemBuilder: (context, index) {
                              final file = files[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 4,
                                ),
                                leading: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: colors.secondaryContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    _isImages ? Icons.image_outlined
                                        : Icons.description_outlined,
                                    color: colors.onSecondaryContainer,
                                  ),
                                ),
                                title: Text(file.entry.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  '${file.path}  ·  ${_size(file.entry.size)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: _isImages ? () => _openImage(file) : null,
                                trailing: IconButton(
                                  tooltip: 'Download',
                                  onPressed: () => _download(file),
                                  icon: const Icon(Icons.download_outlined),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
