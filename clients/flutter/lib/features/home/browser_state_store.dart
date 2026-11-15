import 'package:flutter/foundation.dart';

/// App-scoped browser session state. Keyed by server URL so multiple servers
/// never share navigation or presentation state.
class BrowserStateStore extends ChangeNotifier {
  BrowserStateStore();

  final Map<String, FileBrowserState> _files = {};
  final Map<String, MediaBrowserState> _media = {};

  FileBrowserState fileState(String serverKey) =>
      _files.putIfAbsent(serverKey, FileBrowserState.new);

  MediaBrowserState mediaState(String serverKey, String type) =>
      _media.putIfAbsent('$serverKey::$type', MediaBrowserState.new);

  void updateFile(String serverKey, FileBrowserState state) {
    _files[serverKey] = state;
    notifyListeners();
  }

  void updateMedia(String serverKey, String type, MediaBrowserState state) {
    _media['$serverKey::$type'] = state;
    notifyListeners();
  }
}

@immutable
class FileBrowserState {
  const FileBrowserState({
    this.path = '',
    this.category = 'All',
    this.sortBy = 'name',
    this.gridView = false,
    this.scrollOffset = 0,
  });

  final String path;
  final String category;
  final String sortBy;
  final bool gridView;
  final double scrollOffset;

  FileBrowserState copyWith({
    String? path,
    String? category,
    String? sortBy,
    bool? gridView,
    double? scrollOffset,
  }) => FileBrowserState(
    path: path ?? this.path,
    category: category ?? this.category,
    sortBy: sortBy ?? this.sortBy,
    gridView: gridView ?? this.gridView,
    scrollOffset: scrollOffset ?? this.scrollOffset,
  );
}

@immutable
class MediaBrowserState {
  const MediaBrowserState({
    this.folderPath = '',
    this.selectedVolume,
    this.view = 'all',
    this.sortBy = 'name',
    this.layoutMode = 'grid',
    this.scrollOffset = 0,
  });

  final String folderPath;
  final String? selectedVolume;
  final String view;
  final String sortBy;
  final String layoutMode;
  final double scrollOffset;

  MediaBrowserState copyWith({
    String? folderPath,
    String? selectedVolume,
    bool clearSelectedVolume = false,
    String? view,
    String? sortBy,
    String? layoutMode,
    double? scrollOffset,
  }) => MediaBrowserState(
    folderPath: folderPath ?? this.folderPath,
    selectedVolume: clearSelectedVolume ? null : selectedVolume ?? this.selectedVolume,
    view: view ?? this.view,
    sortBy: sortBy ?? this.sortBy,
    layoutMode: layoutMode ?? this.layoutMode,
    scrollOffset: scrollOffset ?? this.scrollOffset,
  );
}
