import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/pocketlink_file_icon.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';
import '../../core/widgets/liquid_glass_pill.dart';

import '../../core/network/server_api.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/home_activity_store.dart';
import '../home/browser_state_store.dart';
import '../transfers/transfer_manager.dart';
import '../downloads/download_manager_service.dart';
import '../transfers/transfer_manager_screen.dart';
import '../media/persistent_audio_player.dart';
import '../media/now_playing_overlay_controller.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({
    required this.api,
    this.initialPath = '',
    this.initialVolume,
    this.externalDriveRequest = 0,
    this.locationRequest = 0,
    this.uploadRequest = 0,
    this.requestedVolume,
    this.requestedPath = '',
    this.initialCategory = 'All',
    this.showSearch = true,
    this.isActive = false,
    this.onBackAtRoot,
    this.onCanNavigateBackChanged,
    this.onBackHandlerChanged,
    super.key,
  });

  final ServerApi api;
  final String initialPath;
  final String? initialVolume;
  final int externalDriveRequest;
  final int locationRequest;
  final int uploadRequest;
  final String? requestedVolume;
  final String requestedPath;
  final String initialCategory;
  final bool showSearch;
  final bool isActive;
  final VoidCallback? onBackAtRoot;
  final ValueChanged<bool>? onCanNavigateBackChanged;
  final ValueChanged<VoidCallback?>? onBackHandlerChanged;

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _path = '';
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  late final String _stateKey;
  late final BrowserStateStore _browserState;
  String _sortBy = 'name';
  double _pendingScrollOffset = 0;
  int _loadGeneration = 0;
  List<StorageVolume> _volumes = const [];
  String? _selectedVolume;
  bool _openingAudio = false;

  late String _category = widget.initialCategory;
  bool _gridView = false;
  bool _searchExpanded = false;
  bool _storageMenuOpen = false;
  final TextEditingController _searchController = TextEditingController();

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

  int _categoryCount(List<FileEntry> entries, String category) {
    if (category == 'All') return entries.length;
    final extensions = _categoryExtensions[category];
    if (extensions == null) return 0;
    return entries
        .where((item) => !item.isDirectory && extensions.contains(_extension(item)))
        .length;
  }

  PocketLinkFileVisual _fileVisual(FileEntry item, ColorScheme colors) =>
      PocketLinkFileVisuals.resolve(
        name: item.name,
        isDirectory: item.isDirectory,
        colors: colors,
      );

  IconData _iconFor(FileEntry item) =>
      _fileVisual(item, Theme.of(context).colorScheme).icon;

  Color _iconColorFor(FileEntry item, ColorScheme colors) =>
      _fileVisual(item, colors).color;

  @override
  void didUpdateWidget(covariant FileManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uploadRequest != widget.uploadRequest && widget.uploadRequest > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _uploadFile();
      });
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCanNavigateBackChanged?.call(_path.isNotEmpty);
    });
    _category = widget.initialCategory != 'All' ? widget.initialCategory : saved.category;
    _sortBy = saved.sortBy;
    _gridView = saved.gridView;
    _pendingScrollOffset = saved.scrollOffset;
    _selectedVolume = widget.locationRequest > 0 ? widget.requestedVolume : widget.initialVolume ?? saved.selectedVolume;
    _scrollController.addListener(_saveScrollOffset);
    _loadVolumesAndDirectory(selectFirstExternal: widget.locationRequest == 0 && widget.externalDriveRequest > 0);
    if (widget.uploadRequest > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _uploadFile();
      });
    }
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
      _pendingScrollOffset = 0;
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
      widget.onCanNavigateBackChanged?.call(_path.isNotEmpty);
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


  Future<void> _showRecentLocations() async {
    await HomeActivityStore.instance.load();
    if (!mounted) return;
    final recent = HomeActivityStore.instance.itemsForServer(widget.api.baseUrl);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: recent.isEmpty
            ? const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No recent files or folders yet')))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: recent.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                itemBuilder: (context, index) {
                  final item = recent[index];
                  return ListTile(
                    leading: Icon(item.isFolder ? Icons.folder_rounded : Icons.history_rounded),
                    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.path.isEmpty ? 'Storage root' : item.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final parent = item.isFolder ? item.path : item.parentPath;
                      _selectPartition(item.volume).then((_) => _load(parent));
                    },
                  );
                },
              ),
        ),
      ),
    );
  }

  Future<void> _uploadFile() async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
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
    try {
      await DownloadManagerService.instance.enqueueServerFile(
        api: widget.api,
        name: item.name,
        sourcePath: _itemPath(item.name),
        volume: _selectedVolume,
        size: item.size,
      );
      if (mounted) _showError('Added to Downloads: ${item.name}');
    } catch (_) {
      if (mounted) _showError('Could not add ${item.name} to Downloads.');
    }
  }


  Future<void> _showSortOptions() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (sheetContext) {
        final sheetColors = Theme.of(sheetContext).colorScheme;
        const options = [
          ('name', 'Name', Icons.sort_by_alpha_rounded),
          ('newest', 'Newest', Icons.schedule_rounded),
          ('largest', 'Largest', Icons.storage_rounded),
        ];
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: sheetColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sort files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                for (final option in options)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(option.$3),
                    title: Text(option.$2),
                    trailing: _sortBy == option.$1
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, option.$1),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted || selected == _sortBy) return;
    setState(() => _sortBy = selected);
    _saveState();
  }

  void _openTransfers() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const TransferManagerScreen(),
    ));
  }

  static const _audioExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'aiff', 'alac',
  };

  bool _isAudio(FileEntry item) => _audioExtensions.contains(_extension(item));

  Future<void> _openAudio(FileEntry item) async {
    if (_openingAudio) return;
    _openingAudio = true;
    final path = _itemPath(item.name);
    final volume = _selectedVolume;
    await AppLogger.info('Audio open requested', fields: {
      'source': volume == null ? 'internal' : 'external',
      'extension': _extension(item),
    });
    try {
      await PersistentAudioPlayer.instance.openQueue(
        api: widget.api,
        queue: [
          MediaQueueItem(
            title: item.name,
            path: path,
            volume: volume,
            size: item.size,
          ),
        ],
        initialIndex: 0,
        isMusic: true,
      );
      NowPlayingOverlayController.open();
    } catch (error, stackTrace) {
      await AppLogger.error('Could not open Now Playing screen', error: error, stackTrace: stackTrace);
      _showError('Could not open the music player. Check diagnostics for details.');
    } finally {
      _openingAudio = false;
    }
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

  void _syncBackHandler() {
    widget.onBackHandlerChanged?.call(_searchExpanded
        ? () => _setSearchExpanded(false)
        : null);
  }

  void _setSearchExpanded(bool expanded) {
    if (_searchExpanded == expanded) return;
    setState(() => _searchExpanded = expanded);
    _syncBackHandler();
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);
    _saveState();
    _scrollController.removeListener(_saveScrollOffset);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allItems = _listing?.items ?? const <FileEntry>[];
    final fileCount = allItems.where((item) => !item.isDirectory).length;
    final folderCount = allItems.where((item) => item.isDirectory).length;
    final query = _searchController.text.trim().toLowerCase();
    final items = allItems.where((item) => _matchesCategory(item) &&
      (query.isEmpty || item.name.toLowerCase().contains(query))).toList();
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
      final color = _iconColorFor(item, colors);
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_iconFor(item), color: color, size: size),
      );
    }

    Widget fileTile(FileEntry item) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.22))),
        child: SizedBox(height: 60, child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: fileIcon(item),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(item.isDirectory ? 'Folder' : _formatSize(item.size),
              style: TextStyle(color: colors.onSurfaceVariant)),
          onTap: item.isDirectory
              ? () => _load(_itemPath(item.name))
              : _isAudio(item) ? () => _openAudio(item)
              : _isImage(item) ? () => _previewImage(item) : null,
          trailing: SmokedGlassPopoverMenu<String>(
            tooltip: 'More actions',
            items: [
              if (!item.isDirectory)
                const SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded),
              const SmokedGlassPopoverMenuItem(value: 'rename', label: 'Rename', icon: Icons.drive_file_rename_outline_rounded),
              const SmokedGlassPopoverMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true, dividerBefore: true),
            ],
            onSelected: (action) {
              if (action == 'download' && !item.isDirectory) _downloadFile(item);
              if (action == 'rename') _rename(item);
              if (action == 'delete') _delete(item);
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.more_vert_rounded),
            ),
          ),
        )),
      );
    }

    return PopScope(
      canPop: (_searchExpanded && widget.onBackHandlerChanged != null) ||
          (!_searchExpanded && !widget.isActive && _path.isEmpty),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || (_searchExpanded && widget.onBackHandlerChanged != null)) return;
        if (_path.isNotEmpty) {
          _goUp();
        } else if (widget.isActive) {
          widget.onBackAtRoot?.call();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PocketLinkAppBar(
          feathered: true,
          showHome: false,
          automaticallyImplyLeading: false,
          leading: _path.isEmpty
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    child: SizedBox.square(
                      dimension: 38,
                      child: GlassCircleButton(
                        tooltip: 'Back',
                        onPressed: _goUp,
                        child: const Icon(Icons.arrow_back_rounded, size: 18),
                      ),
                    ),
                  ),
                ),
          leadingWidth: _path.isEmpty ? 0 : 62,
          titleSpacing: _path.isEmpty ? 16 : 8,
          title: SmokedGlassPopoverMenu<String>(
            tooltip: 'Choose storage location',
            onOpenChanged: (open) => setState(() => _storageMenuOpen = open),
            items: [
              SmokedGlassPopoverMenuItem(
                value: 'internal',
                label: 'Internal storage',
                icon: Icons.phone_android_rounded,
                trailing: _selectedVolume == null
                    ? const Icon(Icons.check_rounded, size: 18)
                    : null,
              ),
              for (final volume in _volumes)
                SmokedGlassPopoverMenuItem(
                  value: volume.id,
                  label: volume.name,
                  icon: Icons.usb_rounded,
                  trailing: _selectedVolume == volume.id
                      ? const Icon(Icons.check_rounded, size: 18)
                      : null,
                ),
              const SmokedGlassPopoverMenuItem(
                value: 'downloads',
                label: 'Downloads',
                icon: Icons.download_rounded,
                dividerBefore: true,
              ),
              const SmokedGlassPopoverMenuItem(
                value: 'recent',
                label: 'Recent',
                icon: Icons.history_rounded,
              ),
            ],
            onSelected: (value) {
              if (value == 'recent') { _showRecentLocations(); return; }
              if (value == 'internal') { _selectPartition(null); return; }
              if (value == 'downloads') { _selectPartition(null).then((_) => _load('Downloads')); return; }
              _selectPartition(value);
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(_path.isEmpty ? 'Files' : _path.split('/').last,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 6),
                  AnimatedRotation(turns: _storageMenuOpen ? 0.5 : 0, duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 24)),
                ]),
                Text('${folderCount == 1 ? '1 folder' : '$folderCount folders'} • ${fileCount == 1 ? '1 file' : '$fileCount files'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFFA1A7B3))),
              ])),
            ]),
          ),
          actions: [
            if (widget.showSearch) PocketLinkAppBarAction(label: _searchExpanded ? 'Close search' : 'Search files', icon: _searchExpanded ? Icons.close_rounded : Icons.search_rounded, onPressed: () => _setSearchExpanded(!_searchExpanded)),
            PocketLinkAppBarAction(label: 'Upload file', icon: Icons.upload_rounded, onPressed: _uploadFile),
            PocketLinkAppBarAction(label: 'New folder', icon: Icons.create_new_folder_outlined, onPressed: _createFolder),
            PocketLinkAppBarAction(label: 'Sort by...', icon: Icons.sort_rounded,
              onPressed: _showSortOptions, dividerBefore: true),
            PocketLinkAppBarAction(label: _gridView ? 'Switch to list view' : 'Switch to grid view',
              icon: _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              onPressed: () { setState(() => _gridView = !_gridView); _saveState(); }),
            PocketLinkAppBarAction(label: 'Transfers', icon: Icons.swap_vert_rounded, onPressed: _openTransfers, dividerBefore: true),
            PocketLinkAppBarAction(label: 'Refresh', icon: Icons.refresh_rounded, onPressed: _loading ? null : _refreshDirectory),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Builder(builder: (context) {
                final topInset = MediaQuery.paddingOf(context).top +
                    kToolbarHeight +
                    (_searchExpanded ? 64 : 0) +
                    (_path.isNotEmpty ? 38 : 0) +
                    44; // Filter row: 10px outer padding + 34px pill.
                Widget emptyList(String message, {Widget? action}) => ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 104 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    SizedBox(
                      height: 150,
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(message, style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
                          if (action != null) ...[const SizedBox(height: 12), action],
                        ]),
                      ),
                    ),
                  ],
                );

                final Widget content = _error != null
                    ? emptyList(
                        _error!,
                        action: FilledButton.icon(
                          onPressed: _refreshDirectory,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      )
                    : _loading && _listing == null
                        ? const SizedBox.shrink()
                        : items.isEmpty
                            ? emptyList(allItems.isEmpty ? 'This folder is empty' : 'No matching files')
                            : _gridView
                                ? GridView.builder(
                                    controller: _scrollController,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 104 + MediaQuery.paddingOf(context).bottom),
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 190,
                                      mainAxisExtent: 156,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: item.isDirectory
                                            ? () => _load(_itemPath(item.name))
                                            : _isAudio(item)
                                                ? () => _openAudio(item)
                                                : _isImage(item)
                                                    ? () => _previewImage(item)
                                                    : null,
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: colors.surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.32)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                fileIcon(item, size: 26),
                                                const Spacer(),
                                                SmokedGlassPopoverMenu<String>(
                                                  tooltip: 'More actions',
                                                  items: [
                                                    if (!item.isDirectory)
                                                      const SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded),
                                                    const SmokedGlassPopoverMenuItem(value: 'rename', label: 'Rename', icon: Icons.drive_file_rename_outline_rounded),
                                                    const SmokedGlassPopoverMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true, dividerBefore: true),
                                                  ],
                                                  onSelected: (action) {
                                                    if (action == 'download' && !item.isDirectory) _downloadFile(item);
                                                    if (action == 'rename') _rename(item);
                                                    if (action == 'delete') _delete(item);
                                                  },
                                                  child: const Padding(
                                                    padding: EdgeInsets.all(6),
                                                    child: Icon(Icons.more_vert_rounded),
                                                  ),
                                                ),
                                              ]),
                                              const Spacer(),
                                              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                              const SizedBox(height: 3),
                                              Text(item.isDirectory ? 'Folder' : _formatSize(item.size),
                                                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : ListView.separated(
                                    controller: _scrollController,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 104 + MediaQuery.paddingOf(context).bottom),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) => fileTile(items[index]),
                                  );
                return RefreshIndicator(
                  onRefresh: _refreshDirectory,
                  child: content,
                );
              }),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search this folder',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: IconButton(
                              onPressed: () { _searchController.clear(); setState(() {}); },
                              icon: const Icon(Icons.close_rounded),
                            ),
                            filled: true,
                            fillColor: colors.surfaceContainerLow.withValues(alpha: 0.92),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    if (_path.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                        child: SizedBox(
                          height: 30,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                onPressed: () => _load(''),
                                child: Text(_selectedVolume == null ? 'Internal storage' : _volumeName(_selectedVolume!),
                                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                              ),
                              for (var i = 0; i < _path.split('/').where((part) => part.isNotEmpty).length; i++) ...[
                                const Center(child: Icon(Icons.chevron_right_rounded, size: 15)),
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: i == _path.split('/').where((part) => part.isNotEmpty).length - 1
                                      ? null
                                      : () => _load(_path.split('/').where((part) => part.isNotEmpty).take(i + 1).join('/')),
                                  child: Text(_path.split('/').where((part) => part.isNotEmpty).elementAt(i), style: theme.textTheme.labelSmall),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SmokedGlassPopoverMenu<String>(
                          tooltip: 'Filter file types',
                          itemHeight: 44,
                          menuVerticalPadding: 6,
                          itemHorizontalPadding: 14,
                          trailingWidth: 52,
                          items: [
                            for (final category in const ['All', 'Images', 'Videos', 'Music', 'Documents'])
                              SmokedGlassPopoverMenuItem(
                                value: category,
                                label: category,
                                icon: switch (category) {
                                  'Images' => Icons.image_outlined,
                                  'Videos' => Icons.movie_outlined,
                                  'Music' => Icons.music_note_outlined,
                                  'Documents' => Icons.description_outlined,
                                  _ => Icons.apps_rounded,
                                },
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(
                                    '${_categoryCount(allItems, category)}',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3)),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 20,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _category == category
                                          ? const Icon(Icons.check_rounded, size: 16)
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                ]),
                              ),
                          ],
                          onSelected: (category) {
                            setState(() => _category = category);
                            _saveState();
                          },
                          child: SmokedGlassSurface(
                            radius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.filter_list_rounded, size: 17),
                                const SizedBox(width: 7),
                                Text('Filter: $_category', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                  ],
                ),
              ),
            ),
          ],
        )
      ),
    );
  }

}
