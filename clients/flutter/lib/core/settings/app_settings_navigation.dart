part of 'app_settings.dart';

extension AppSettingsNavigation on AppSettings {
  Future<void> setNavigationLayout({
    required List<String> order,
    required Set<String> visibleItems,
  }) async {
    if (order.length != AppSettings.navigationDefaults.length ||
        order.toSet().length != AppSettings.navigationDefaults.length ||
        !order.toSet().containsAll(AppSettings.navigationDefaults) ||
        !visibleItems.contains('home') ||
        visibleItems.length < 2 ||
        !visibleItems.every(AppSettings.navigationDefaults.contains)) {
      throw ArgumentError('Invalid navigation layout');
    }
    _navigationOrder = List.of(order);
    _visibleNavigationItems = Set.of(visibleItems);
    _notifySettingsChanged();
    final orderSnapshot = List<String>.of(_navigationOrder);
    final visibilitySnapshot = AppSettings.navigationDefaults
        .where(_visibleNavigationItems.contains)
        .toList(growable: false);
    final write = _navigationWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.setString(AppSettings._navigationOrderKey, jsonEncode(orderSnapshot)),
        preferences.setString(AppSettings._navigationVisibilityKey, jsonEncode(visibilitySnapshot)),
      ]);
    });
    _navigationWrite = write;
    await write;
  }

  Future<void> resetNavigationLayout() async {
    _navigationOrder = List.of(AppSettings.navigationDefaults);
    _visibleNavigationItems = Set.of(AppSettings.navigationDefaults);
    _notifySettingsChanged();
    final write = _navigationWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(AppSettings._navigationOrderKey),
        preferences.remove(AppSettings._navigationVisibilityKey),
      ]);
    });
    _navigationWrite = write;
    await write;
  }

  Future<void> setMusicButtonShortcuts(List<String> shortcuts) async {
    if (shortcuts.isEmpty ||
        shortcuts.toSet().length != shortcuts.length ||
        !shortcuts.every(AppSettings.musicButtonShortcutDestinations.contains)) {
      throw ArgumentError('Invalid Music button shortcuts');
    }
    _musicButtonShortcuts = List.of(shortcuts);
    _notifySettingsChanged();
    final snapshot = List<String>.of(_musicButtonShortcuts);
    final write = _musicButtonShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(AppSettings._musicButtonShortcutsKey, jsonEncode(snapshot));
    });
    _musicButtonShortcutsWrite = write;
    await write;
  }

  Future<void> resetMusicButtonShortcuts() async {
    _musicButtonShortcuts = List.of(AppSettings.musicButtonShortcutDefaults);
    _notifySettingsChanged();
    final write = _musicButtonShortcutsWrite.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.remove(AppSettings._musicButtonShortcutsKey),
        preferences.remove(AppSettings._legacyFloatingShortcutsKey),
      ]);
    });
    _musicButtonShortcutsWrite = write;
    await write;
  }

  Future<void> setHomeSectionOrder(List<String> order) async {
    if (order.length != AppSettings.homeSectionDefaults.length ||
        order.toSet().length != AppSettings.homeSectionDefaults.length ||
        !order.toSet().containsAll(AppSettings.homeSectionDefaults)) {
      throw ArgumentError('Invalid Home section order');
    }
    _homeSectionOrder = List.of(order);
    _notifySettingsChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(AppSettings._homeSectionOrderKey, jsonEncode(_homeSectionOrder));
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
      if (quickActions != null) AppSettings._storage.write(key: AppSettings._quickActionsKey, value: '$quickActions'),
      if (library != null) AppSettings._storage.write(key: AppSettings._libraryKey, value: '$library'),
      if (recentFiles != null) AppSettings._storage.write(key: AppSettings._recentKey, value: '$recentFiles'),
    ]);
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      if (globalSearch != null) preferences.setBool(AppSettings._homeSearchKey, globalSearch),
      if (activeTransfers != null) preferences.setBool(AppSettings._homeTransfersKey, activeTransfers),
    ]);
  }
}
