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
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _category = 'All';
  bool _gridView = false;

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
        if (savedPath == null) token.cancel('Save cancelled by user');
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allItems = _listing?.items ?? const <FileEntry>[];
    final query = _searchQuery.trim().toLowerCase();
    final items = allItems.where((item) {
      if (!_matchesCategory(item)) return false;
      return query.isEmpty || item.name.toLowerCase().contains(query);
    }).toList(growable: false);

    Widget fileIcon(FileEntry item, {double size = 24}) {
      final color = item.isDirectory ? colors.primary : colors.secondary;
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(_iconFor(item), color: color, size: size),
      );
    }

    Widget fileTile(FileEntry item) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          leading: fileIcon(item),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w650)),
          subtitle: Text(item.isDirectory ? 'Folder' : _formatSize(item.size),
              style: TextStyle(color: colors.onSurfaceVariant)),
          onTap: item.isDirectory
              ? () => _load(_itemPath(item.name))
              : _isImage(item) ? () => _previewImage(item) : null,
          trailing: PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (action) {
              if (action == 'download' && !item.isDirectory) _downloadFile(item);
              if (action == 'rename') _rename(item);
              if (action == 'delete') _delete(item);
            },
            itemBuilder: (_) => [
              if (!item.isDirectory)
                const PopupMenuItem(value: 'download', child: Text('Download')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _path.isNotEmpty) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('File manager', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(tooltip: 'Transfers', onPressed: _openTransfers,
                icon: const Icon(Icons.swap_vert_rounded)),
            IconButton(tooltip: 'Upload file', onPressed: _uploadFile,
                icon: const Icon(Icons.cloud_upload_outlined)),
            IconButton(tooltip: 'New folder', onPressed: _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined)),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colors.primaryContainer, colors.surfaceContainerHighest],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(Icons.folder_copy_rounded, color: colors.primary, size: 25),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'Go to parent folder',
                        onPressed: _path.isEmpty ? null : _goUp,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Text(_path.isEmpty ? 'Internal storage' : _path.split('/').last,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_path.isEmpty ? 'Your files, all in one place' : 'Internal storage  /  $_path',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    Row(children: [
                      _summaryPill(Icons.folder_outlined, '${allItems.where((e) => e.isDirectory).length} folders'),
                      const SizedBox(width: 8),
                      _summaryPill(Icons.insert_drive_file_outlined, '${allItems.where((e) => !e.isDirectory).length} files'),
                    ]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search files and folders',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: colors.primary, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: Row(children: [
                Expanded(child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final category in const ['All', 'Images', 'Videos', 'Music', 'Documents'])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) => setState(() => _category = category),
                          showCheckmark: false,
                        ),
                      ),
                  ],
                )),
                IconButton(
                  tooltip: _gridView ? 'List view' : 'Grid view',
                  onPressed: () => setState(() => _gridView = !_gridView),
                  icon: Icon(_gridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
                ),
                const SizedBox(width: 8),
              ]),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Material(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: TextStyle(color: colors.onErrorContainer))),
                    ]),
                  ),
                ),
              ),
            Expanded(
              child: _error != null
                  ? Center(child: FilledButton.icon(onPressed: () => _load(),
                      icon: const Icon(Icons.refresh), label: const Text('Try again')))
                  : _loading && _listing == null
                      ? const SizedBox.shrink()
                      : items.isEmpty
                          ? RefreshIndicator(
                              onRefresh: () => _load(),
                              child: ListView(physics: const AlwaysScrollableScrollPhysics(),
                                children: [SizedBox(height: 150, child: Center(child: Text(
                                  allItems.isEmpty ? 'This folder is empty' : 'No matching files',
                                  style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                                )))],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _load(),
                              child: _gridView
                                  ? GridView.builder(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 190, mainAxisExtent: 156,
                                        crossAxisSpacing: 10, mainAxisSpacing: 10,
                                      ),
                                      itemCount: items.length,
                                      itemBuilder: (context, index) {
                                        final item = items[index];
                                        return InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: item.isDirectory ? () => _load(_itemPath(item.name))
                                              : _isImage(item) ? () => _previewImage(item) : null,
                                          child: Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: colors.surfaceContainerLow,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Row(children: [
                                                fileIcon(item, size: 26),
                                                const Spacer(),
                                                PopupMenuButton<String>(
                                                  padding: EdgeInsets.zero,
                                                  onSelected: (action) {
                                                    if (action == 'download' && !item.isDirectory) _downloadFile(item);
                                                    if (action == 'rename') _rename(item);
                                                    if (action == 'delete') _delete(item);
                                                  },
                                                  itemBuilder: (_) => [
                                                    if (!item.isDirectory) const PopupMenuItem(value: 'download', child: Text('Download')),
                                                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                                  ],
                                                ),
                                              ]),
                                              const Spacer(),
                                              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                              const SizedBox(height: 3),
                                              Text(item.isDirectory ? 'Folder' : _formatSize(item.size),
                                                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                                            ]),
                                          ),
                                        );
                                      },
                                    )
                                  : ListView.separated(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                      itemCount: items.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, index) => fileTile(items[index]),
                                    ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPill(IconData icon, String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
