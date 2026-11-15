import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../media/now_playing_screen.dart';
import '../media/persistent_audio_player.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_manager_screen.dart';

class StorageBrowserScreen extends StatefulWidget {
  const StorageBrowserScreen({
    required this.api,
    this.initialVolume,
    this.initialPath = '',
    this.showSearch = true,
    super.key,
  });
  final ServerApi api;
  final String? initialVolume;
  final String initialPath;
  final bool showSearch;

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _gridView = false;

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
        _volume = volumes.any((item) => item.id == widget.initialVolume)
            ? widget.initialVolume
            : (available.isNotEmpty
                ? available.first.id
                : (volumes.isEmpty ? null : volumes.first.id));
        _path = widget.initialPath;
      });
      if (_volume != null) await _loadDirectory(widget.initialPath);
    } on DioException catch (error) {
      if (mounted) setState(() => _error = switch (error.response?.statusCode) {
        401 => 'HomeServer rejected the saved login (401). Go back to the connection screen and enter the current server admin password. The SAF bridge token is separate.',
        403 => 'HomeServer denied access to external storage (403). Check the server account permissions.',
        404 => 'SSD support is not enabled on the HomeServer backend yet.',
        _ => error.message ?? 'Could not detect external storage.',
      });
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
      setState(() => _error = switch (error.response?.statusCode) {
        401 => 'HomeServer rejected the saved login (401). Go back to the connection screen and enter the current server admin password. The SAF bridge token is separate.',
        403 => 'Android denied access to this SSD.',
        404 => 'Storage folder not found or permission not granted.',
        _ => error.message ?? 'Could not read this folder.',
      });
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
    final volume = _volume;
    if (volume == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _message('Could not read the selected file.');
        return;
      }
      final completed = await TransferManager.instance.run(
        name: file.name,
        direction: 'Upload',
        location: '${selectedVolumeName(volume)} · ${_path.isEmpty ? 'Root' : _path}',
        operation: (token, progress) => widget.api.uploadStorageFile(
          volume,
          _path,
          file.name,
          bytes,
          cancelToken: token,
          onSendProgress: progress,
        ),
      );
      if (!mounted) return;
      if (completed) {
        await _loadDirectory();
        _message('Uploaded ${file.name}');
      } else {
        _message('Upload did not complete. Check Transfers for details.');
      }
    } catch (_) {
      _message('Could not select or upload this file.');
    }
  }

  String selectedVolumeName(String id) {
    for (final volume in _volumes) {
      if (volume.id == id) return volume.name;
    }
    return 'External storage';
  }

  static const _audioExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'aiff', 'alac',
  };

  bool _isAudio(FileEntry item) {
    final extension = item.name.contains('.')
        ? item.name.split('.').last.toLowerCase()
        : '';
    return _audioExtensions.contains(extension);
  }

  Future<void> _openAudio(FileEntry item) async {
    final volume = _volume;
    if (volume == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingScreen(
          api: widget.api,
          queue: [
            MediaQueueItem(
              title: item.name,
              path: _itemPath(item.name),
              volume: volume,
              size: item.size,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(FileEntry item) async {
    final volume = _volume;
    if (volume == null) return;
    try {
      setState(() => _progress = 0);
      final bytes = await widget.api.downloadStorageFile(
        volume,
        _itemPath(item.name),
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;

      final temp = await getTemporaryDirectory();
      final openDirectory = Directory('${temp.path}/homeserver-open');
      await openDirectory.create(recursive: true);
      final localFile = File('${openDirectory.path}/${item.name}');
      await localFile.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(localFile.path);
      if (result.type != ResultType.done && mounted) {
        _message(result.message.isNotEmpty
            ? result.message
            : 'No installed app can open this file type.');
      }
    } on DioException catch (error) {
      _message(error.message ?? 'Could not download file for opening.');
    } catch (error) {
      _message('Could not open file: $error');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _download(FileEntry item) async {
    final volume = _volume;
    if (volume == null) return;
    final completed = await TransferManager.instance.run(
      name: item.name,
      direction: 'Download',
      location: '${selectedVolumeName(volume)} · ${_path.isEmpty ? 'Root' : _path}',
      operation: (token, progress) async {
        final bytes = await widget.api.downloadStorageFile(
          volume,
          _itemPath(item.name),
          cancelToken: token,
          onReceiveProgress: progress,
        );
        if (token.isCancelled) return;
        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${item.name}',
          fileName: item.name,
          initialDirectory: AppSettings.instance.downloadDirectory,
          bytes: bytes,
        );
        if (savedPath == null) token.cancel('Save cancelled by user');
      },
    );
    if (!mounted) return;
    _message(completed
        ? 'Download complete: ${item.name}'
        : 'Download did not complete. Check Transfers for details.');
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

  Future<void> _goUp() async {
    if (_path.isEmpty) return;
    final parts = _path.split('/')..removeLast();
    await _loadDirectory(parts.join('/'));
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
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
    final items = allItems.where((item) => query.isEmpty || item.name.toLowerCase().contains(query)).toList(growable: false);
    final selectedVolumes = _volumes.where((item) => item.id == _volume).toList(growable: false);
    final selected = selectedVolumes.isEmpty ? null : selectedVolumes.first;

    Widget iconFor(FileEntry item) {
      final icon = item.isDirectory
          ? Icons.folder_rounded
          : _isAudio(item) ? Icons.audio_file_rounded : Icons.insert_drive_file_outlined;
      final color = item.isDirectory ? colors.primary : colors.secondary;
      return Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: color, size: 25),
      );
    }

    void handleAction(String action, FileEntry item) {
      if (action == 'open' && !item.isDirectory) _isAudio(item) ? _openAudio(item) : _openFile(item);
      if (action == 'download' && !item.isDirectory) _download(item);
      if (action == 'rename') _rename(item);
      if (action == 'delete') _delete(item);
    }

    Widget menu(FileEntry item) => PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (action) => handleAction(action, item),
      itemBuilder: (_) => [
        if (!item.isDirectory) const PopupMenuItem(value: 'open', child: Text('Open')),
        if (!item.isDirectory) const PopupMenuItem(value: 'download', child: Text('Download')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );

    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _path.isNotEmpty) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('External storage', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(tooltip: 'Transfers', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferManagerScreen())), icon: const Icon(Icons.swap_vert_rounded)),
            IconButton(tooltip: 'Upload', onPressed: _volume == null ? null : _upload, icon: const Icon(Icons.cloud_upload_outlined)),
            IconButton(tooltip: 'New folder', onPressed: _volume == null ? null : _createFolder, icon: const Icon(Icons.create_new_folder_outlined)),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _loadVolumes, icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [colors.tertiaryContainer, colors.surfaceContainerHighest],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: colors.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(15)),
                    child: Icon(Icons.usb_rounded, color: colors.tertiary, size: 25)),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: 'Go to parent folder',
                    onPressed: _path.isEmpty ? null : _goUp,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(selected?.name ?? 'Choose a drive',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(_path.isEmpty ? 'External drive  /  Root' : '${selected?.name ?? 'Drive'}  /  $_path',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(children: [
                  _volumePill(Icons.folder_outlined, '${allItems.where((e) => e.isDirectory).length} folders'),
                  const SizedBox(width: 8),
                  _volumePill(Icons.insert_drive_file_outlined, '${allItems.where((e) => !e.isDirectory).length} files'),
                  const SizedBox(width: 8),
                  _volumePill(selected?.writable == true ? Icons.edit_outlined : Icons.visibility_outlined,
                    selected?.writable == true ? 'Read & write' : 'Read only'),
                ]),
              ]),
            ),
          ),
          if (_volumes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: DropdownButtonFormField<String>(
                initialValue: _volume,
                decoration: InputDecoration(
                  labelText: 'Storage location',
                  prefixIcon: const Icon(Icons.storage_rounded),
                  filled: true, fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
                ),
                items: _volumes.map((item) => DropdownMenuItem(
                  value: item.id,
                  child: Text('${item.name}${item.available ? '' : ' · Not connected'}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() { _volume = value; _path = ''; _listing = null; _searchController.clear(); _searchQuery = ''; });
                  _loadDirectory('');
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search this drive folder',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                  icon: const Icon(Icons.close_rounded)),
                filled: true, fillColor: colors.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide(color: colors.primary, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 42, child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text('${items.length} items', style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
            ),
            const Spacer(),
            IconButton(
              tooltip: _gridView ? 'List view' : 'Grid view',
              onPressed: () => setState(() => _gridView = !_gridView),
              icon: Icon(_gridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            ),
            const SizedBox(width: 8),
          ])),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_progress != null) LinearProgressIndicator(value: _progress),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.error)),
            ),
          Expanded(
            child: _error != null
                ? Center(child: FilledButton.icon(onPressed: _loadVolumes, icon: const Icon(Icons.refresh), label: const Text('Try again')))
                : _loading && _listing == null
                    ? const SizedBox.shrink()
                    : items.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _loadDirectory,
                            child: ListView(physics: const AlwaysScrollableScrollPhysics(),
                              children: [SizedBox(height: 140, child: Center(child: Text(
                                allItems.isEmpty ? 'This folder is empty' : 'No matching files',
                                style: TextStyle(color: colors.onSurfaceVariant))))]))
                        : RefreshIndicator(
                            onRefresh: _loadDirectory,
                            child: _gridView
                                ? GridView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(16, 10, 16, 104 + MediaQuery.paddingOf(context).bottom),
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 190, mainAxisExtent: 158,
                                      crossAxisSpacing: 10, mainAxisSpacing: 10),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: item.isDirectory ? () => _loadDirectory(_itemPath(item.name))
                                            : () => _isAudio(item) ? _openAudio(item) : _openFile(item),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Row(children: [iconFor(item), const Spacer(), menu(item)]),
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
                                    padding: EdgeInsets.fromLTRB(16, 10, 16, 104 + MediaQuery.paddingOf(context).bottom),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return Card(
                                        margin: EdgeInsets.zero, elevation: 0,
                                        color: colors.surfaceContainerLow,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                          leading: iconFor(item),
                                          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w600)),
                                          subtitle: Text(item.isDirectory ? 'Folder' : _formatSize(item.size),
                                            style: TextStyle(color: colors.onSurfaceVariant)),
                                          onTap: item.isDirectory ? () => _loadDirectory(_itemPath(item.name))
                                              : () => _isAudio(item) ? _openAudio(item) : _openFile(item),
                                          trailing: menu(item),
                                        ),
                                      );
                                    },
                                  ),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _volumePill(IconData icon, String label) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14), const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      ),
    );
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
}
