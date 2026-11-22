import 'package:flutter/foundation.dart';

/// App-scoped media-library navigation and presentation state, isolated per
/// server and media type (for example, Music and Videos).
class MediaBrowserStateStore extends ChangeNotifier {
  final Map<String, MediaBrowserState> _states = {};

  MediaBrowserState stateFor(String serverKey, String mediaType) =>
      _states.putIfAbsent('$serverKey::$mediaType', MediaBrowserState.new);

  void update(String serverKey, String mediaType, MediaBrowserState state) {
    _states['$serverKey::$mediaType'] = state;
    notifyListeners();
  }
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
