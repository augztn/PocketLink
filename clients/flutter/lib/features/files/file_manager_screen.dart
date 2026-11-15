import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_manager_screen.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({
    required this.api,
    this.initialPath = '',
    super.key,
  });

  final ServerApi api;
  final String initialPath;

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _path = '';
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;
  double? _transferProgress;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _category = 'All';

  static const Map<String, Set<String>> _categoryExtensions = {
    'Images': {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif'},
    'Videos': {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', '3gp', 'mpeg', 'mpg'},
    'Music': {'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma'},
    'Documents': {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'rtf', 'csv'},
  };

  String _extension(FileEntry item) {
    final dot = item.name.lastIndexOf('.');
    return dot < 0 ? '' : item.name.substring(dot + 1).toLowerCase();
  }

  bool _matchesCategory(FileEntry item) {
    if (item.isDirectory || _category == 'All') return true;
    return _categoryExtensions[_category]?.contains(_extension(item)) ?? false;
  }

  IconData _iconFor(FileEntry item) {
    if (item.isDirectory) return Icons.folder_rounded;
    final extension = _extension(item);
    if (_categoryExtensions['Images']!.contains(extension)) {
      return Icons.image_outlined;
    }
    if (_categoryExtensions['Videos']!.contains(extension)) {
      return Icons.video_file_outlined;
    }
    if (_categoryExtensions['Music']!.contains(extension)) {
      return Icons.audio_file_outlined;
    }
    if (_categoryExtensions['Documents']!.contains(extension)) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _load(widget.initialPath);
  }

  Future<void> _load([String? path]) async {
    final target = path ?? _path;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.listDirectory(target);
      if (!mounted) return;
      setState(() {
        _path = result.path == '.' ? '' : result.path;
        _listing = result;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not read this folder.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) return 'Login expired or credentials are incorrect.';
    if (status == 403) return 'Access denied.';
    if (status == 404) return 'Folder not found.';
    return error.message ?? 'Server request failed.';
  }

  String _itemPath(String name) => _path.isEmpty ? name : '$_path/$name';

  Future<String?> _askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  Future<void> _uploadFile() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _showError('Could not read the selected file on this device.');
        return;
      }
      if (bytes.length > 100 * 1024 * 1024) {
        _showError('File exceeds the server 100 MB upload limit.');
        return;
      }

      final completed = await TransferManager.instance.run(
        name: file.name,
        direction: 'Upload',
        location: _path.isEmpty ? 'Internal storage' : _path,
        operation: (token, progress) => widget.api.uploadFile(
          _path,
          file.name,
          bytes,
          cancelToken: token,
          onSendProgress: progress,
        ),
      );
      if (!mounted) return;
      if (completed) {
        _showError('Upload complete: ${file.name}');
        await _load();
      } else {
        _showError('Upload did not complete. Check Transfers for details.');
      }
    } catch (_) {
      _showError('Unable to select or upload this file.');
    }
  }

  Future<void> _downloadFile(FileEntry item) async {
    final completed = await TransferManager.instance.run(
      name: item.name,
      direction: 'Download',
      location: _path.isEmpty ? 'Internal storage' : _path,
      operation: (token, progress) async {
        final bytes = await widget.api.downloadFile(
          _itemPath(item.name),
          cancelToken: token,
          onReceiveProgress: progress,
        );
        if (token.isCancelled) return;
        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${item.name}',
          fileName: item.name,
          bytes: bytes,
        );
        if (savedPath == null) {
          throw StateError('Save location was not selected.');
        }
      },
    );
    if (!mounted) return;
    _showError(completed
        ? 'Download complete: ${item.name}'
        : 'Download did not complete. Check Transfers for details.');
  }

  void _openTransfers() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const TransferManagerScreen(),
    ));
  }

  bool _isImage(FileEntry item) {
    final extension = item.name.toLowerCase().split('.').last;
    return const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(extension);
  }

  Future<void> _previewImage(FileEntry item) async {
    if (item.size > 20 * 1024 * 1024) {
      _showError('Image preview is limited to 20 MB. Download the file instead.');
      return;
    }
    try {
      final bytes = await widget.api.downloadFile(_itemPath(item.name));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('This image format could not be previewed.'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } on DioException catch (error) {
      _showError(_messageFor(error));
    } catch (_) {
      _showError('Unable to preview this image.');
    }
  }

  Future<void> _createFolder() async {
    final name = await _askName('Create folder');
    if (name == null) return;
    try {
      await widget.api.createFolder(_path, name);
      await _load();
    } on DioException catch (error) {
      _showError(_messageFor(error));
    }
  }

  Future<void> _rename(FileEntry item) async {
    final name = await _askName('Rename item', initial: item.name);
    if (name == null || name == item.name) return;
    try {
      await widget.api.renameItem(_itemPath(item.name), name);
      await _load();
    } on DioException catch (error) {
      _showError(_messageFor(error));
    }
  }

  Future<void> _delete(FileEntry item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${item.name}"? Folders must be empty.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteItem(_itemPath(item.name));
      await _load();
    } on DioException catch (error) {
      _showError(_messageFor(error));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _goUp() async {
    if (_path.isEmpty) return;
    final parts = _path.split('/');
    parts.removeLast();
    await _load(parts.join('/'));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = bytes / 1024;
    var index = 0;
    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(1)} ${units[index]}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _listing?.items ?? const <FileEntry>[];
    final query = _searchQuery.trim().toLowerCase();
    final items = allItems.where((item) {
      if (!_matchesCategory(item)) return false;
      return query.isEmpty || item.name.toLowerCase().contains(query);
    }).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            tooltip: 'Upload file',
            onPressed: _uploadFile,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'New folder',
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
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
            title: Text(_path.isEmpty ? 'HomeServer storage' : _path),
            subtitle: Text('${allItems.length} items'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search this folder',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final category in const [
                  'All', 'Images', 'Videos', 'Music', 'Documents'
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_transferProgress != null)
            LinearProgressIndicator(value: _transferProgress),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              )),
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
                    : items.isEmpty
                        ? Center(
                            child: Text(
                              allItems.isEmpty
                                  ? 'This folder is empty.'
                                  : 'No matching files.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return ListTile(
                                leading: Icon(_iconFor(item)),
                                title: Text(item.name),
                                subtitle: Text(item.isDirectory
                                    ? 'Folder'
                                    : _formatSize(item.size)),
                                onTap: item.isDirectory
                                    ? () => _load(_itemPath(item.name))
                                    : _isImage(item)
                                        ? () => _previewImage(item)
                                        : null,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'download' && !item.isDirectory) {
                                      _downloadFile(item);
                                    }
                                    if (action == 'rename') _rename(item);
                                    if (action == 'delete') _delete(item);
                                  },
                                  itemBuilder: (_) => [
                                    if (!item.isDirectory)
                                      const PopupMenuItem(
                                        value: 'download',
                                        child: Text('Download'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
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
