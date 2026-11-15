import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/home_server_app_bar.dart';
import '../../core/widgets/compact_search_field.dart';

import '../../core/network/server_api.dart';
import '../../core/storage/home_activity_store.dart';
import '../home/browser_state_store.dart';
import '../../core/settings/app_settings.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_manager_screen.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({
    required this.api,
    this.initialPath = '',
    this.initialVolume,
    this.externalDriveRequest = 0,
    this.locationRequest = 0,
    this.requestedVolume,
    this.requestedPath = '',
    this.initialCategory = 'All',
    this.showSearch = true,
    this.isActive = false,
    this.onBackAtRoot,
    super.key,
  });

  final ServerApi api;
  final String initialPath;
  final String? initialVolume;
  final int externalDriveRequest;
  final int locationRequest;
  final String? requestedVolume;
  final String requestedPath;
  final String initialCategory;
  final bool showSearch;
  final bool isActive;
  final VoidCallback? onBackAtRoot;

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _path = '';
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final String _stateKey;
  late final BrowserStateStore _browserState;
  String _sortBy = 'name';
  double _pendingScrollOffset = 0;
  int _loadGeneration = 0;
  List<StorageVolume> _volumes = const [];
  String? _selectedVolume;

  String _searchQuery = '';
  late String _category = widget.initialCategory;
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
  void didUpdateWidget(covariant FileManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      _category = widget.initialCategory;
    }
    if (oldWidget.locationRequest != widget.locationRequest && widget.locationRequest > 0) {
      _navigateToRequestedLocation();
    } else if (oldWidget.externalDriveRequest != widget.externalDriveRequest &&
        widget.externalDriveRequest > 0) {
      _selectFirstExternalDrive();
    }
    if (oldWidget.initialVolume != widget.initialVolume && widget.initialVolume != null) {
      _selectPartition(widget.initialVolume);
    }
  }

  @override
  void initState() {
    super.initState();
    _stateKey = widget.api.baseUrl;
    _browserState = Provider.of<BrowserStateStore>(context, listen: false);
    final saved = _browserState.fileState(_stateKey);
    _path = widget.locationRequest > 0 ? widget.requestedPath : (widget.initialPath.isNotEmpty ? widget.initialPath : saved.path);
    _category = widget.initialCategory != 'All' ? widget.initialCategory : saved.category;
    _sortBy = saved.sortBy;
    _gridView = saved.gridView;
    _pendingScrollOffset = saved.scrollOffset;
    _selectedVolume = widget.locationRequest > 0 ? widget.requestedVolume : widget.initialVolume ?? saved.selectedVolume;
    _scrollController.addListener(_saveScrollOffset);
    _loadVolumesAndDirectory(selectFirstExternal: widget.locationRequest == 0 && widget.externalDriveRequest > 0);
  }

  void _restoreScrollOffset() {
    if (!mounted || !_scrollController.hasClients || _pendingScrollOffset <= 0) return;
    _scrollController.jumpTo(_pendingScrollOffset.clamp(0, _scrollController.position.maxScrollExtent).toDouble());
    _pendingScrollOffset = 0;
  }

  void _saveState({String? path}) {
    final current = _browserState.fileState(_stateKey);
    _browserState.updateFile(_stateKey, current.copyWith(
      path: path ?? _path,
      category: _category,
      sortBy: _sortBy,
      gridView: _gridView,
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : current.scrollOffset,
      selectedVolume: _selectedVolume,
      clearSelectedVolume: _selectedVolume == null,
    ));
  }

  void _saveScrollOffset() => _saveState();

  Future<void> _navigateToRequestedLocation() async {
    final volume = widget.requestedVolume;
    try {
      var available = _volumes;
      try {
        final volumes = await widget.api.listStorageVolumes();
        available = volumes.where((item) => item.available).toList();
      } catch (_) {
        if (volume != null) rethrow;
      }
      if (!mounted) return;
      if (volume != null && !available.any((item) => item.id == volume)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That storage drive is no longer mounted.')),
        );
        return;
      }
      setState(() {
        _volumes = available;
        _selectedVolume = volume;
        _path = widget.requestedPath;
        _listing = null;
        _searchController.clear();
        _searchQuery = '';
        _pendingScrollOffset = 0;
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
      _saveState(path: _path);
      await _load(_path);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that storage location.')),
      );
    }
  }

  Future<void> _selectFirstExternalDrive() async {
    try {
      final volumes = await widget.api.listStorageVolumes();
      if (!mounted) return;
      final available = volumes.where((volume) => volume.available).toList();
      setState(() => _volumes = available);
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No mounted external drives found.')),
        );
        return;
      }
      await _selectPartition(available.first.id);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load external drives.')),
      );
    }
  }

  Future<void> _loadVolumesAndDirectory({bool selectFirstExternal = false}) async {
    try {
      final volumes = await widget.api.listStorageVolumes();
      if (!mounted) return;
      final available = volumes.where((volume) => volume.available).toList();
      setState(() {
        _volumes = available;
        if (selectFirstExternal && available.isNotEmpty) {
          _selectedVolume = available.first.id;
          _path = '';
          _pendingScrollOffset = 0;
        }
        if (_selectedVolume != null && !available.any((v) => v.id == _selectedVolume)) {
          _selectedVolume = null;
          _path = '';
          _pendingScrollOffset = 0;
        }
      });
    } catch (_) {}
    await _load(_path);
  }

  Future<void> _selectPartition(String? volumeId) async {
    setState(() {
      _selectedVolume = volumeId; _path = ''; _listing = null;
      _searchController.clear(); _searchQuery = ''; _pendingScrollOffset = 0;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
    _saveState(path: '');
    await _load('');
  }

  Future<void> _refreshDirectory() async {
    widget.api.invalidateDirectoryCache();
    await _load();
  }

  Future<void> _load([String? path]) async {
    final generation = ++_loadGeneration;
    final target = path ?? _path;
    if (target != _path) { _pendingScrollOffset = 0; if (_scrollController.hasClients) _scrollController.jumpTo(0); }
    setState(() { _loading = true; _error = null; });
    try {
      final result = _selectedVolume == null
          ? await widget.api.listDirectory(target)
          : await widget.api.listStorageDirectory(_selectedVolume!, target);
      if (!mounted || generation != _loadGeneration) return;
      final previousPath = _path;
      final previousVolume = _selectedVolume;
      setState(() { _path = result.path == '.' ? '' : result.path; _listing = result; _saveState(path: _path); });
      if (_path.isNotEmpty && (_path != previousPath || _selectedVolume != previousVolume)) {
        HomeActivityStore.instance.recordFolder(serverUrl: widget.api.baseUrl, path: _path, volume: _selectedVolume);
      }
    } on DioException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = _messageFor(error));
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = 'Could not read this folder.');
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollOffset());
      }
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
  String _volumeName(String id) {
    for (final volume in _volumes) {
      if (volume.id == id) return volume.name;
    }
    return id;
  }

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

  void _focusSearch() {
    if (!widget.showSearch) return;
    _searchFocusNode.requestFocus();
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

      final volume = _selectedVolume;
      final completed = await TransferManager.instance.run(
        name: file.name, direction: 'Upload',
        location: '${volume == null ? 'Internal storage' : _volumeName(volume)} · ${_path.isEmpty ? 'Root' : _path}',
        operation: (token, progress) => volume == null
          ? widget.api.uploadFile(_path, file.name, bytes, cancelToken: token, onSendProgress: progress)
          : widget.api.uploadStorageFile(volume, _path, file.name, bytes, cancelToken: token, onSendProgress: progress),
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
        final bytes = _selectedVolume == null
          ? await widget.api.downloadFile(_itemPath(item.name), cancelToken: token, onReceiveProgress: progress)
          : await widget.api.downloadStorageFile(_selectedVolume!, _itemPath(item.name), cancelToken: token, onReceiveProgress: progress);
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
      final bytes = _selectedVolume == null ? await widget.api.downloadFile(_itemPath(item.name)) : await widget.api.downloadStorageFile(_selectedVolume!, _itemPath(item.name));
      if (!mounted) return;
      HomeActivityStore.instance.recordFile(
        serverUrl: widget.api.baseUrl,
        title: item.name,
        path: _itemPath(item.name),
        volume: _selectedVolume,
      );
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
      if (_selectedVolume == null) { await widget.api.createFolder(_path, name); } else { await widget.api.createStorageFolder(_selectedVolume!, _path, name); }
      await _load();
    } on DioException catch (error) {
      _showError(_messageFor(error));
    }
  }

  Future<void> _rename(FileEntry item) async {
    final name = await _askName('Rename item', initial: item.name);
    if (name == null || name == item.name) return;
    try {
      if (_selectedVolume == null) { await widget.api.renameItem(_itemPath(item.name), name); } else { await widget.api.renameStorageItem(_selectedVolume!, _itemPath(item.name), name); }
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
      if (_selectedVolume == null) { await widget.api.deleteItem(_itemPath(item.name)); } else { await widget.api.deleteStorageItem(_selectedVolume!, _itemPath(item.name)); }
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
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
    _saveState();
    _scrollController.removeListener(_saveScrollOffset);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    }).toList();
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      if (_sortBy == 'largest') return b.size.compareTo(a.size);
      if (_sortBy == 'newest') {
        return (DateTime.tryParse(b.modified)?.millisecondsSinceEpoch ?? 0)
            .compareTo(DateTime.tryParse(a.modified)?.millisecondsSinceEpoch ?? 0);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

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
              style: const TextStyle(fontWeight: FontWeight.w600)),
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
      canPop: !widget.isActive && _path.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_path.isNotEmpty) {
          _goUp();
        } else if (widget.isActive) {
          widget.onBackAtRoot?.call();
        }
      },
      child: Scaffold(
        appBar: HomeServerAppBar(
          title: const Text('Files', style: TextStyle(fontWeight: FontWeight.w800)),
          onHome: () => _load(''),
          actionsBeforeHome: widget.showSearch ? [
            IconButton(
              tooltip: 'Search files',
              onPressed: _focusSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          ] : const [],
          actions: [
            HomeServerAppBarAction(label: 'Transfers', icon: Icons.swap_vert_rounded, onPressed: _openTransfers),
            HomeServerAppBarAction(label: 'Upload file', icon: Icons.cloud_upload_outlined, onPressed: _uploadFile),
            HomeServerAppBarAction(label: 'New folder', icon: Icons.create_new_folder_outlined, onPressed: _createFolder),
            HomeServerAppBarAction(label: 'Refresh', icon: Icons.refresh_rounded, onPressed: _loading ? null : _refreshDirectory),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.folder_copy_rounded, color: colors.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => showModalBottomSheet<void>(
                            context: context, backgroundColor: colors.surfaceContainerLow, showDragHandle: true,
                            builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              ListTile(leading: const Icon(Icons.phone_android_rounded), title: const Text('Internal storage'),
                                trailing: _selectedVolume == null ? const Icon(Icons.check_rounded) : null,
                                onTap: () { Navigator.pop(sheetContext); _selectPartition(null); }),
                              for (final volume in _volumes) ListTile(leading: const Icon(Icons.usb_rounded),
                                title: Text(volume.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(volume.id),
                                trailing: _selectedVolume == volume.id ? const Icon(Icons.check_rounded) : null,
                                onTap: () { Navigator.pop(sheetContext); _selectPartition(volume.id); }),
                              if (_volumes.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No mounted external drives')),
                            ])),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _path.isEmpty ? (_selectedVolume == null ? 'Internal storage' : _volumeName(_selectedVolume!)) : _path.split('/').last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down_rounded, size: 21),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${allItems.where((e) => e.isDirectory).length} folders • ${allItems.where((e) => !e.isDirectory).length} files',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: colors.secondaryContainer,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Go to parent folder',
                          visualDensity: VisualDensity.compact,
                          onPressed: _path.isEmpty ? null : _goUp,
                          icon: Icon(Icons.arrow_upward_rounded, color: colors.onSecondaryContainer, size: 19),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.showSearch) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: CompactSearchField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  hintText: 'Search files and folders',
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_path.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _load(''),
                        child: Text(
                          _selectedVolume == null ? 'Internal storage' : _volumeName(_selectedVolume!),
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                      for (var i = 0; i < _path.split('/').where((part) => part.isNotEmpty).length; i++) ...[
                        const Center(child: Icon(Icons.chevron_right_rounded, size: 15)),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: i == _path.split('/').where((part) => part.isNotEmpty).length - 1
                              ? null
                              : () => _load(_path.split('/').where((part) => part.isNotEmpty).take(i + 1).join('/')),
                          child: Text(
                            _path.split('/').where((part) => part.isNotEmpty).elementAt(i),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),

            SizedBox(
              height: 40,
              child: Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final category in const ['All', 'Images', 'Videos', 'Music', 'Documents'])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _category == category,
                              onSelected: (_) { setState(() => _category = category); _saveState(); },
                              showCheckmark: false,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Sort files',
                  onSelected: (value) { setState(() => _sortBy = value); _saveState(); },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'name', child: Text('Name')),
                    PopupMenuItem(value: 'newest', child: Text('Newest')),
                    PopupMenuItem(value: 'largest', child: Text('Largest')),
                  ],
                  icon: const Icon(Icons.sort_rounded),
                ),
                IconButton(
                  tooltip: _gridView ? 'List view' : 'Grid view',
                  onPressed: () { setState(() => _gridView = !_gridView); _saveState(); },
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
                  ? Center(child: FilledButton.icon(onPressed: _refreshDirectory,
                      icon: const Icon(Icons.refresh), label: const Text('Try again')))
                  : _loading && _listing == null
                      ? const SizedBox.shrink()
                      : items.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _refreshDirectory,
                              child: ListView(physics: const AlwaysScrollableScrollPhysics(),
                                children: [SizedBox(height: 150, child: Center(child: Text(
                                  allItems.isEmpty ? 'This folder is empty' : 'No matching files',
                                  style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                                )))],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _refreshDirectory,
                              child: _gridView
                                  ? GridView.builder(
                                      controller: _scrollController,
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.fromLTRB(16, 12, 16, 104 + MediaQuery.paddingOf(context).bottom),
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
                                      controller: _scrollController,
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.fromLTRB(16, 12, 16, 104 + MediaQuery.paddingOf(context).bottom),
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

}
