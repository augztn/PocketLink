import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../../core/widgets/pocketlink_file_icon.dart';

import '../../core/network/server_api.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/home_activity_store.dart';
import 'file_browser_state_store.dart';
import 'file_entry_tile.dart';
import 'file_browser_directory_content.dart';
import 'file_browser_header_content.dart';
import 'file_browser_storage_title.dart';
import 'file_browser_sort_sheet.dart';
import 'file_browser_recent_locations.dart';
import 'file_browser_dialogs.dart';
import 'file_browser_image_preview.dart';
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
  late final FileBrowserStateStore _browserState;
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
    if (category == 'All') return entries.where((item) => !item.isDirectory).length;
    final extensions = _categoryExtensions[category];
    if (extensions == null) return 0;
    return entries
        .where((item) => !item.isDirectory && extensions.contains(_extension(item)))
        .length;
  }

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
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.onBackHandlerChanged != widget.onBackHandlerChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncBackHandler();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _stateKey = widget.api.baseUrl;
    _browserState = Provider.of<FileBrowserStateStore>(context, listen: false);
    final saved = _browserState.stateFor(_stateKey);
    _path = widget.locationRequest > 0 ? widget.requestedPath : (widget.initialPath.isNotEmpty ? widget.initialPath : saved.path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCanNavigateBackChanged?.call(_path.isNotEmpty);
      _syncBackHandler();
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
    final current = _browserState.stateFor(_stateKey);
    _browserState.update(_stateKey, current.copyWith(
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
      widget.onCanNavigateBackChanged?.call(_path.isNotEmpty);
      _syncBackHandler();
      _saveState(path: _path);
      await _load(_path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that storage location.')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load external drives.')),
        );
      }
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
      widget.onCanNavigateBackChanged?.call(_path.isNotEmpty);
      _syncBackHandler();
    } catch (_) {}
    await _load(_path);
  }

  Future<void> _selectPartition(String? volumeId) async {
    setState(() {
      _selectedVolume = volumeId; _path = ''; _listing = null;
      _pendingScrollOffset = 0;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
    widget.onCanNavigateBackChanged?.call(false);
    _syncBackHandler();
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
      // Folder depth is state-driven in the embedded Files tab, so refresh
      // the shell's system-Back callback whenever a directory load commits.
      _syncBackHandler();
      if (_path.isNotEmpty && (_path != previousPath || _selectedVolume != previousVolume)) {
        await HomeActivityStore.instance.recordFolder(
          serverUrl: widget.api.baseUrl,
          path: _path,
          volume: _selectedVolume,
        );
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

  Future<String?> _askName(String title, {String initial = ''}) =>
      showFileBrowserNameDialog(
        context: context,
        title: title,
        initial: initial,
      );


  Future<void> _showRecentLocations() async {
    await HomeActivityStore.instance.load();
    if (!mounted) return;
    await showFileBrowserRecentLocations(
      context: context,
      recent: HomeActivityStore.instance.itemsForServer(widget.api.baseUrl),
      onSelected: (item) {
        final parent = item.isFolder ? item.path : item.parentPath;
        _selectPartition(item.volume).then((_) => _load(parent));
      },
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
    final selected = await showFileBrowserSortOptions(
      context: context,
      selectedSort: _sortBy,
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

  VoidCallback? _openActionFor(FileEntry item) {
    if (item.isDirectory) return () => _load(_itemPath(item.name));
    if (_isAudio(item)) return () => _openAudio(item);
    if (_isImage(item)) return () => _previewImage(item);
    return null;
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
      await HomeActivityStore.instance.recordFile(
        serverUrl: widget.api.baseUrl,
        title: item.name,
        path: _itemPath(item.name),
        volume: _selectedVolume,
      );
      await showFileBrowserImagePreview(
        context: context,
        name: item.name,
        bytes: bytes,
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
    final confirmed = await confirmFileBrowserDelete(
      context: context,
      itemName: item.name,
    );
    if (!confirmed) return;
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
    if (widget.onBackAtRoot != null && !widget.isActive) {
      widget.onBackHandlerChanged?.call(null);
      return;
    }
    final handler = _searchExpanded
        ? () => _setSearchExpanded(false)
        : _path.isNotEmpty
            ? _goUp
            : null;
    widget.onBackHandlerChanged?.call(handler);
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

    final embeddedTab = widget.onBackAtRoot != null;
    return PopScope(
      // Embedded Files delegates all Back decisions to the HomeScreen shell.
      // Keep this local fallback only for standalone FileManager routes.
      canPop: embeddedTab || (!_searchExpanded && _path.isEmpty),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || embeddedTab) return;
        if (_searchExpanded) {
          _setSearchExpanded(false);
        } else if (_path.isNotEmpty) {
          _goUp();
        } else if (embeddedTab) {
          widget.onBackAtRoot?.call();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PocketLinkAppBar(
          feathered: true,
          showHome: false,
          automaticallyImplyLeading: false,
          leading: _path.isEmpty && embeddedTab
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    child: SizedBox.square(
                      dimension: 38,
                      child: GlassCircleButton(
                        tooltip: 'Back',
                        onPressed: _path.isEmpty
                            ? () => Navigator.of(context).maybePop()
                            : _goUp,
                        child: const Icon(Icons.arrow_back_rounded, size: 18),
                      ),
                    ),
                  ),
                ),
          leadingWidth: _path.isEmpty && embeddedTab ? 0 : 62,
          titleSpacing: _path.isEmpty && embeddedTab ? 16 : 8,
          title: FileBrowserStorageTitle(
            path: _path,
            folderCount: folderCount,
            fileCount: fileCount,
            volumes: _volumes,
            selectedVolume: _selectedVolume,
            menuOpen: _storageMenuOpen,
            onOpenChanged: (open) => setState(() => _storageMenuOpen = open),
            onSelected: (value) {
              if (value == 'recent') {
                _showRecentLocations();
                return;
              }
              if (value == 'internal') {
                _selectPartition(null);
                return;
              }
              if (value == 'downloads') {
                _selectPartition(null).then((_) => _load('Downloads'));
                return;
              }
              _selectPartition(value);
            },
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
                final topInset = LayoutInsetsScope.of(context).topClearance +
                    (_searchExpanded ? 64 : 0) +
                    (_path.isNotEmpty ? 38 : 0) +
                    34; // Filter row follows the shared measured header.
                return FileBrowserDirectoryContent(
                  allItemsEmpty: allItems.isEmpty,
                  items: items,
                  initialLoading: _loading && _listing == null,
                  error: _error,
                  gridView: _gridView,
                  scrollController: _scrollController,
                  topInset: topInset,
                  bottomInset: LayoutInsetsScope.of(context).bottomClearance,
                  colors: colors,
                  textTheme: theme.textTheme,
                  onRefresh: _refreshDirectory,
                  itemBuilder: (item, grid) {
                    final visual = PocketLinkFileVisuals.resolve(
                      name: item.name,
                      isDirectory: item.isDirectory,
                      colors: colors,
                    );
                    return FileEntryTile(
                      item: item,
                      grid: grid,
                      colors: colors,
                      icon: visual.icon,
                      iconColor: visual.color,
                      formattedSize: _formatSize(item.size),
                      onOpen: _openActionFor(item),
                      onDownload: () => _downloadFile(item),
                      onRename: () => _rename(item),
                      onDelete: () => _delete(item),
                    );
                  },
                );
              }),
            ),
            Positioned(
              top: LayoutInsetsScope.of(context).topClearance - 10,
              left: 0,
              right: 0,
              child: FileBrowserHeaderContent(
                searchExpanded: _searchExpanded,
                searchController: _searchController,
                path: _path,
                storageLabel: _selectedVolume == null
                    ? 'Internal storage'
                    : _volumeName(_selectedVolume!),
                selectedCategory: _category,
                categoryCounts: {
                  for (final category in const [
                    'All', 'Images', 'Videos', 'Music', 'Documents',
                  ])
                    category: _categoryCount(allItems, category),
                },
                loading: _loading,
                hasListing: _listing != null,
                error: _error,
                colors: colors,
                onSearchChanged: (_) => setState(() {}),
                onClearSearch: () {
                  _searchController.clear();
                  setState(() {});
                },
                onNavigate: _load,
                onCategorySelected: (category) {
                  setState(() => _category = category);
                  _saveState();
                },
              ),
            ),
          ],
        )
      ),
    );
  }

}