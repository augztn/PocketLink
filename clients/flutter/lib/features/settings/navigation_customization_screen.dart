import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../home/navigation_dock.dart';
import 'widgets/settings_components.dart';

class NavigationCustomizationScreen extends StatefulWidget {
  const NavigationCustomizationScreen({this.initialSearchQuery, super.key});

  final String? initialSearchQuery;

  @override
  State<NavigationCustomizationScreen> createState() =>
      _NavigationCustomizationScreenState();
}

class _NavigationCustomizationScreenState
    extends State<NavigationCustomizationScreen> {
  final _settings = AppSettings.instance;
  late List<String> _order;
  late Set<String> _visibleItems;
  late final TextEditingController _searchController;
  String _query = '';
  final Map<String, GlobalKey> _destinationKeys = {};

  static const _details = <String, ({String label, String description, IconData icon})>{
    'home': (label: 'Home', description: 'Your dashboard', icon: Icons.home_rounded),
    'explore': (label: 'Explore', description: 'Browse server media and folders', icon: Icons.explore_rounded),
    'files': (label: 'Files', description: 'Manage files and storage', icon: Icons.folder_rounded),
    'browse': (label: 'Browse / Music', description: 'Music player shortcut', icon: Icons.music_note_rounded),
  };

  @override
  void initState() {
    super.initState();
    _order = List.of(_settings.navigationOrder);
    _visibleItems = Set.of(_settings.visibleNavigationItems);
    _query = widget.initialSearchQuery ?? '';
    _searchController = TextEditingController(text: _query);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFirstMatch());
  }

  void _setQuery(String value) {
    setState(() => _query = value);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFirstMatch());
  }

  void _scrollToFirstMatch() {
    if (_query.trim().isEmpty || !mounted) return;
    for (final id in _order) {
      if (!_matchesDestination(id)) continue;
      final target = _destinationKeys[id]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: 0.18,
        );
      }
      break;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesDestination(String id) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return true;
    final detail = _details[id]!;
    final corpus = '${detail.label} ${detail.description} destination $id'.toLowerCase();
    return query.split(RegExp(r'[^a-z0-9]+')).where((token) => token.isNotEmpty).every(corpus.contains);
  }

  Future<void> _save() async {
    try {
      await _settings.setNavigationLayout(
        order: _order,
        visibleItems: _visibleItems,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save navigation layout.')),
        );
      }
    }
  }

  Future<void> _reset() async {
    try {
      await _settings.resetNavigationLayout();
      if (!mounted) return;
      setState(() {
        _order = [
          ...AppSettings.navigationDefaults.where((id) => id != 'browse'),
          'browse',
        ];
        _visibleItems = Set.of(AppSettings.navigationDefaults);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navigation bar reset to default')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reset navigation bar.')),
        );
      }
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _order.removeAt(oldIndex);
      _order.insert(newIndex, item);
    });
    _save();
  }

  void _setVisible(String id, bool visible) {
    if (id == 'home') return;
    if (!visible && _visibleItems.length <= 2) return;
    setState(() {
      if (visible) {
        _visibleItems.add(id);
      } else {
        _visibleItems.remove(id);
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDefault = _settings.navigationLayoutIsDefault;
    final visibleOrder = _order.where(_matchesDestination).toList(growable: false);

    return Scaffold(
      appBar: const PocketLinkAppBar(
        title: Text('Navigation', style: TextStyle(fontSize: 20)),
      ),
      body: ListView(
        padding: settingsListPadding(context),
        children: [
          TextField(
            controller: _searchController,
            onChanged: _setQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search destinations',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        _setQuery('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SettingsSectionHeader('Live preview'),
          Text(
            'Your dock updates as you rearrange or hide destinations.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SettingsGroupCard(
            padding: const EdgeInsets.all(8),
            children: [
              FloatingNavigationDock(
              order: _order,
              visibleItems: _visibleItems,
              selectedIndex: 0,
              onSelect: (_) {},
              onBrowsePressed: () {},
              preview: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SettingsSectionHeader('Navigation destinations'),
          Text(
            'Drag destinations, including Browse / Music, to change the dock order.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SettingsGroupCard(children: [
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: visibleOrder.length,
              onReorderItem: _query.isEmpty ? _reorder : (_, __) {},
              onReorderStart: (_) => HapticFeedback.selectionClick(),
              onReorderEnd: (_) => HapticFeedback.lightImpact(),
              itemBuilder: (context, index) {
                final id = visibleOrder[index];
                final detail = _details[id]!;
                final visible = _visibleItems.contains(id);
                final matches = _query.isNotEmpty && _matchesDestination(id);
                return Column(
                  key: _destinationKeys.putIfAbsent(id, GlobalKey.new),
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: matches ? colors.primary.withValues(alpha: 0.13) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: matches ? Border.all(color: colors.primary.withValues(alpha: 0.24)) : null,
                      ),
                      child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      leading: Icon(detail.icon, color: colors.onSurfaceVariant),
                      title: Text(detail.label),
                      subtitle: Text(
                        id == 'home' ? 'Always visible' : detail.description,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (id != 'home')
                            Switch(
                              value: visible,
                              onChanged: !visible && _visibleItems.length <= 2
                                  ? null
                                  : (value) => _setVisible(id, value),
                            ),
                          ReorderableDelayedDragStartListener(
                            index: index,
                            enabled: true,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: index == 0
                                    ? colors.onSurface.withValues(alpha: 0.25)
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                    if (index != visibleOrder.length - 1)
                      const Divider(height: 1),
                  ],
                );
              },
            ),
          ]),
          if (_query.isNotEmpty && visibleOrder.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No matching navigation settings found.'),
            ),
          const SizedBox(height: 12),
          Text(
            'Keep at least two destinations visible. Home cannot be hidden, but it can be moved.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: isDefault ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset to Default'),
          ),
        ],
      ),
    );
  }
}
