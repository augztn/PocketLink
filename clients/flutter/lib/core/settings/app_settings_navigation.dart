part of 'app_settings.dart';

extension AppSettingsNavigation on AppSettings {
  Future<void> setNavigationLayout({
    required List<String> order,
    required Set<String> visibleItems,
  }) async {
    if (order.length != navigationDefaults.length ||
        order.toSet().length != navigationDefaults.length ||
        !order.toSet().containsAll(navigationDefaults) ||
        !visibleItems.contains('home') ||
        visibleItems.length < 2 ||
        !visibleItems.every(navigationDefaults.contains)) {
      throw ArgumentError('Invalid navigation layout');
    }
    _navigationOrder = List.of(order);
    _visibleNavigationItems = Set.of(visibleItems);
    _notifySettingsChanged();
    final orderSnapshot = List<String>.of(_navigationOrder);
    final visibilitySnapshot = navigationDefaults
        .where(_visibleNavigationItems.contains)
        .toList(growable: false);
    final write = _navigationWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.setString(_navigationOrderKey, jsonEncode(orderSnapshot)),
        preferences.setString(_navigationVisibilityKey, jsonEncode(visibilitySnapshot)),
      ]);
    });
    _navigationWrite = write;
    await write;
  }

  Future<void> resetNavigationLayout() async {
    _navigationOrder = List.of(navigationDefaults);
    _visibleNavigationItems = Set.of(navigationDefaults);
    _notifySettingsChanged();
    final write = _navigationWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(_navigationOrderKey),
        preferences.remove(_navigationVisibilityKey),
      ]);
    });
    _navigationWrite = write;
    await write;
  }

  Future<void> setMusicButtonShortcuts(List<String> shortcuts) async {
    if (shortcuts.isEmpty ||
        shortcuts.toSet().length != shortcuts.length ||
        !shortcuts.every(musicButtonShortcutDestinations.contains)) {
      throw ArgumentError('Invalid Music button shortcuts');
    }
    _musicButtonShortcuts = List.of(shortcuts);
    _notifySettingsChanged();
    final snapshot = List<String>.of(_musicButtonShortcuts);
    final write = _musicButtonShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_musicButtonShortcutsKey, jsonEncode(snapshot));
    });
    _musicButtonShortcutsWrite = write;
    await write;
  }

  Future<void> resetMusicButtonShortcuts() async {
    _musicButtonShortcuts = List.of(musicButtonShortcutDefaults);
    _notifySettingsChanged();
    final write = _musicButtonShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(_musicButtonShortcutsKey),
        preferences.remove(_legacyFloatingShortcutsKey),
      ]);
    });
    _musicButtonShortcutsWrite = write;
    await write;
  }

  Future<void> setHomeSectionOrder(List<String> order) async {
    if (order.length != homeSectionDefaults.length ||
        order.toSet().length != homeSectionDefaults.length ||
        !order.toSet().containsAll(homeSectionDefaults)) {
      throw ArgumentError('Invalid Home section order');
    }
    _homeSectionOrder = List.of(order);
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_homeSectionOrderKey, jsonEncode(_homeSectionOrder));
  }

  Future<void> setHomeSections({
    bool? quickActions,
    bool? library,
    bool? recentFiles,
    bool? globalSearch,
    bool? activeTransfers,
  }) async {
    if (quickActions != null) _showQuickActions = quickActions;
    if (library != null) _showLibrary = library;
    if (recentFiles != null) _showRecentFiles = recentFiles;
    if (globalSearch != null) _showGlobalSearch = globalSearch;
    if (activeTransfers != null) _showActiveTransfers = activeTransfers;
    _notifySettingsChanged();
    await Future.wait([
      if (quickActions != null) _storage.write(key: _quickActionsKey, value: '$quickActions'),
      if (library != null) _storage.write(key: _libraryKey, value: '$library'),
      if (recentFiles != null) _storage.write(key: _recentKey, value: '$recentFiles'),
    ]);
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (globalSearch != null) preferences.setBool(_homeSearchKey, globalSearch),
      if (activeTransfers != null) preferences.setBool(_homeTransfersKey, activeTransfers),
    ]);
  }
}
