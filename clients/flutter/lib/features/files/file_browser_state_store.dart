import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';

/// App-scoped Files navigation and presentation state, isolated per server.
class FileBrowserStateStore extends ChangeNotifier {
  final Map<String, FileBrowserState> _states = {};

  FileBrowserState stateFor(String serverKey) =>
      _states.putIfAbsent(serverKey, FileBrowserState.new);

  void update(String serverKey, FileBrowserState state) {
    AppLogger.event('files.browser_state_updated', category: 'files',
      component: 'file_browser_state',
      fields: {'has_selected_volume': state.selectedVolume != null,
        'category': state.category, 'sort_by': state.sortBy, 'grid_view': state.gridView});
    _states[serverKey] = state;
    notifyListeners();
  }
}

@immutable
class FileBrowserState {
  const FileBrowserState({
    this.path = '',
    this.selectedVolume,
    this.category = 'All',
    this.sortBy = 'name',
    this.gridView = false,
    this.scrollOffset = 0,
  });

  final String path;
  final String? selectedVolume;
  final String category;
  final String sortBy;
  final bool gridView;
  final double scrollOffset;

  FileBrowserState copyWith({
    String? path,
    String? selectedVolume,
    bool clearSelectedVolume = false,
    String? category,
    String? sortBy,
    bool? gridView,
    double? scrollOffset,
  }) => FileBrowserState(
    path: path ?? this.path,
    selectedVolume: clearSelectedVolume ? null : selectedVolume ?? this.selectedVolume,
    category: category ?? this.category,
    sortBy: sortBy ?? this.sortBy,
    gridView: gridView ?? this.gridView,
    scrollOffset: scrollOffset ?? this.scrollOffset,
  );
}
