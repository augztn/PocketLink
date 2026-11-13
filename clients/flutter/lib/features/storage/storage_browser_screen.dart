import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';

class StorageBrowserScreen extends StatefulWidget {
  const StorageBrowserScreen({required this.api, super.key});
  final ServerApi api;

  @override
  State<StorageBrowserScreen> createState() => _StorageBrowserScreenState();
}

class _StorageBrowserScreenState extends State<StorageBrowserScreen> {
  List<StorageVolume> _volumes = const [];
  String? _volume;
  String _path = '';
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _loadVolumes();
  }

  String _itemPath(String name) => _path.isEmpty ? name : '$_path/$name';

  Future<void> _loadVolumes() async {
    setState(() { _loading = true; _error = null; });
    try {
      final volumes = await widget.api.listStorageVolumes();
      if (!mounted) return;
      final available = volumes.where((item) => item.available).toList();
      setState(() {
        _volumes = volumes;
        _volume = available.isNotEmpty ? available.first.id : (volumes.isEmpty ? null : volumes.first.id);
      });
      if (_volume != null) await _loadDirectory('');
    } on DioException catch (error) {
      if (mounted) setState(() => _error = error.response?.statusCode == 404
          ? 'SSD support is not enabled on the HomeServer backend yet.'
          : error.message ?? 'Could not detect external storage.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not detect external storage.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDirectory([String? path]) async {
    final volume = _volume;
    if (volume == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.listStorageDirectory(volume, path ?? _path);
      if (!mounted) return;
      setState(() {
        _path = result.path == '.' ? '' : result.path;
        _listing = result;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.response?.statusCode == 403
          ? 'Android denied access to this SSD.'
          : error.response?.statusCode == 404
              ? 'Storage folder not found or permission not granted.'
              : error.message ?? 'Could not read this folder.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read this folder.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _ask(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  Future<void> _createFolder() async {
    final name = await _ask('New folder');
    if (name == null || _volume == null) return;
    try {
      await widget.api.createStorageFolder(_volume!, _path, name);
      await _loadDirectory();
    } on DioException catch (error) {
      _message(error.message ?? 'Could not create folder.');
    }
  }

  Future<void> _upload() async {
    if (_volume == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) { _message('Could not read the selected file.'); return; }
      setState(() => _progress = 0);
      final target = _path.isEmpty ? file.name : '$_path/${file.name}';
      await widget.api.uploadStorageFile(
        _volume!, target, file.name, bytes,
        onSendProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _progress = sent / total);
        },
      );
      await _loadDirectory();
      _message('Uploaded ${file.name}');
    } on DioException catch (error) {
      _message(error.message ?? 'Upload failed.');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _download(FileEntry item) async {
    if (_volume == null) return;
    try {
      setState(() => _progress = 0);
      final bytes = await widget.api.downloadStorageFile(
        _volume!, _itemPath(item.name),
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${item.name}', fileName: item.name, bytes: bytes,
      );
      if (saved != null) _message('Saved to $saved');
    } on DioException catch (error) {
      _message(error.message ?? 'Download failed.');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _rename(FileEntry item) async {
    final name = await _ask('Rename item', initial: item.name);
    if (name == null || name == item.name || _volume == null) return;
    try {
      await widget.api.renameStorageItem(_volume!, _itemPath(item.name), name);
      await _loadDirectory();
    } on DioException catch (error) { _message(error.message ?? 'Rename failed.'); }
  }

  Future<void> _delete(FileEntry item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || _volume == null) return;
    try {
      await widget.api.deleteStorageItem(_volume!, _itemPath(item.name));
      await _loadDirectory();
    } on DioException catch (error) { _message(error.message ?? 'Delete failed.'); }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _listing?.items ?? const <FileEntry>[];
    final matches = _volumes.where((item) => item.id == _volume);
    final selected = matches.isEmpty ? null : matches.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('External SSDs'),
        actions: [
          IconButton(tooltip: 'Upload', onPressed: _volume == null ? null : _upload, icon: const Icon(Icons.upload_file)),
          IconButton(tooltip: 'New folder', onPressed: _volume == null ? null : _createFolder, icon: const Icon(Icons.create_new_folder_outlined)),
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _loadVolumes, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        if (_volumes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<String>(
              initialValue: _volume,
              decoration: const InputDecoration(labelText: 'Storage location'),
              items: _volumes.map((item) => DropdownMenuItem(
                value: item.id,
                child: Text('${item.name}${item.available ? '' : ' · Not connected'}'),
              )).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() { _volume = value; _path = ''; _listing = null; });
                _loadDirectory('');
              },
            ),
          ),
        if (selected != null)
          ListTile(
            leading: const Icon(Icons.usb),
            title: Text(selected.name),
            subtitle: Text(selected.available
                ? (selected.writable ? 'Connected · Read and write' : 'Connected · Read only')
                : 'Not connected or permission not granted'),
          ),
        ListTile(
          leading: IconButton(
            tooltip: 'Go up',
            onPressed: _path.isEmpty ? null : () {
              final parts = _path.split('/')..removeLast();
              _loadDirectory(parts.join('/'));
            },
            icon: const Icon(Icons.arrow_upward),
          ),
          title: Text(_path.isEmpty ? 'Root' : _path, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Android Storage Access Framework'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_progress != null) LinearProgressIndicator(value: _progress),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
        Expanded(
          child: _error != null
              ? Center(child: FilledButton(onPressed: _loadVolumes, child: const Text('Retry')))
              : _loading && _listing == null
                  ? const SizedBox.shrink()
                  : items.isEmpty
                      ? const Center(child: Text('This folder is empty.'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              leading: Icon(item.isDirectory ? Icons.folder : Icons.insert_drive_file_outlined),
                              title: Text(item.name),
                              subtitle: Text(item.isDirectory ? 'Folder' : '${item.size} bytes'),
                              onTap: item.isDirectory ? () => _loadDirectory(_itemPath(item.name)) : null,
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'download' && !item.isDirectory) _download(item);
                                  if (action == 'rename') _rename(item);
                                  if (action == 'delete') _delete(item);
                                },
                                itemBuilder: (_) => [
                                  if (!item.isDirectory) const PopupMenuItem(value: 'download', child: Text('Download')),
                                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
