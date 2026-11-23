import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../home/navigation_dock.dart';
import 'widgets/settings_components.dart';

class NavigationCustomizationScreen extends StatefulWidget {
  const NavigationCustomizationScreen({super.key});

  @override
  State<NavigationCustomizationScreen> createState() =>
      _NavigationCustomizationScreenState();
}

class _NavigationCustomizationScreenState
    extends State<NavigationCustomizationScreen> {
  final _settings = AppSettings.instance;
  late List<String> _order;
  late Set<String> _visibleItems;

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

    return Scaffold(
      appBar: const PocketLinkAppBar(
        title: Text('Navigation', style: TextStyle(fontSize: 20)),
      ),
      body: ListView(
        padding: settingsListPadding(context),
        children: [
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
              itemCount: _order.length,
              onReorderItem: _reorder,
              onReorderStart: (_) => HapticFeedback.selectionClick(),
              onReorderEnd: (_) => HapticFeedback.lightImpact(),
              itemBuilder: (context, index) {
                final id = _order[index];
                final detail = _details[id]!;
                final visible = _visibleItems.contains(id);
                return Column(
                  key: ValueKey(id),
                  children: [
                    ListTile(
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
                    if (index != _order.length - 1)
                      const Divider(height: 1),
                  ],
                );
              },
            ),
          ]),
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
