import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';

/// App-scoped media-library navigation and presentation state, isolated per
/// server and media type (for example, Music and Videos).
class MediaBrowserStateStore extends ChangeNotifier {
  final Map<String, MediaBrowserState> _states = {};

  MediaBrowserState stateFor(String serverKey, String mediaType) =>
      _states.putIfAbsent('$serverKey::$mediaType', MediaBrowserState.new);

  void update(String serverKey, String mediaType, MediaBrowserState state) {
    final key = '$serverKey::$mediaType';
    final previous = _states[key] ?? const MediaBrowserState();
    if (previous == state) return;

    _states[key] = state;
    // Scroll offsets are persisted silently. They change on every scroll tick
    // but are not navigation state and must not rebuild listeners or emit events.
    if (previous.samePresentationState(state)) return;

    AppLogger.event('media.browser_state_updated', category: 'media',
      component: 'media_browser_state',
      fields: {'media_type': mediaType, 'has_selected_volume': state.selectedVolume != null,
        'view': state.view, 'sort_by': state.sortBy, 'layout_mode': state.layoutMode});
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

  bool samePresentationState(MediaBrowserState other) =>
      folderPath == other.folderPath &&
      selectedVolume == other.selectedVolume &&
      view == other.view &&
      sortBy == other.sortBy &&
      layoutMode == other.layoutMode;

  @override
  bool operator ==(Object other) =>
      other is MediaBrowserState &&
      samePresentationState(other) &&
      scrollOffset == other.scrollOffset;

  @override
  int get hashCode => Object.hash(
        folderPath,
        selectedVolume,
        view,
        sortBy,
        layoutMode,
        scrollOffset,
      );

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
