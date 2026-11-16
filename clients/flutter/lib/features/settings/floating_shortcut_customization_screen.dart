import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/home_server_app_bar.dart';

class FloatingShortcutCustomizationScreen extends StatefulWidget {
  const FloatingShortcutCustomizationScreen({super.key});

  @override
  State<FloatingShortcutCustomizationScreen> createState() =>
      _FloatingShortcutCustomizationScreenState();
}

class _FloatingShortcutCustomizationScreenState
    extends State<FloatingShortcutCustomizationScreen> {
  final _settings = AppSettings.instance;
  late List<String> _shortcuts = List.of(_settings.floatingShortcuts);
  bool _saving = false;

  static const _details = <String, ({String label, String description, IconData icon})>{
    'explore': (label: 'Explore', description: 'Browse all destinations', icon: Icons.explore_rounded),
    'files': (label: 'Files', description: 'Browse server folders', icon: Icons.folder_rounded),
    'music': (label: 'Music', description: 'Browse your music library', icon: Icons.music_note_rounded),
    'videos': (label: 'Videos', description: 'Browse movies and clips', icon: Icons.play_circle_fill_rounded),
    'photos': (label: 'Photos', description: 'Browse your photo collection', icon: Icons.photo_library_rounded),
    'documents': (label: 'Documents', description: 'Browse PDFs and documents', icon: Icons.description_rounded),
    'favorites': (label: 'Favorites', description: 'Open favourite photos', icon: Icons.favorite_rounded),
    'upload': (label: 'Upload', description: 'Choose a file to upload', icon: Icons.cloud_upload_rounded),
  };

  void _toggle(String id, bool enabled) {
    setState(() {
      if (enabled) {
        if (!_shortcuts.contains(id)) _shortcuts.add(id);
      } else if (_shortcuts.length > 1) {
        _shortcuts.remove(id);
      }
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _shortcuts.removeAt(oldIndex);
      _shortcuts.insert(newIndex, item);
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _settings.setFloatingShortcuts(_shortcuts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Floating shortcuts saved')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save floating shortcuts')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    try {
      await _settings.resetFloatingShortcuts();
      if (!mounted) return;
      setState(() => _shortcuts = List.of(AppSettings.floatingShortcutDefaults));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Floating shortcuts reset to default')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reset floating shortcuts')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: HomeServerAppBar(
        title: const Text('Customize Floating Shortcuts'),
        actions: [
          IconButton(
            tooltip: 'Save shortcuts',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text('Pinned destinations', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            'The first shortcut is the primary action and sets the collapsed button icon. Drag to reorder.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _shortcuts.length,
            onReorder: _reorder,
            itemBuilder: (context, index) {
              final id = _shortcuts[index];
              final detail = _details[id]!;
              return ListTile(
                key: ValueKey(id),
                leading: Icon(detail.icon, color: colors.primary),
                title: Text(detail.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(index == 0 ? 'Primary · ${detail.description}' : detail.description),
                trailing: ReorderableDelayedDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 24),
          Text('Available destinations', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final entry in _details.entries)
            CheckboxListTile(
              value: _shortcuts.contains(entry.key),
              onChanged: (value) => _toggle(entry.key, value ?? false),
              secondary: Icon(entry.value.icon),
              title: Text(entry.value.label),
              subtitle: Text(entry.value.description),
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset shortcuts to default'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save shortcuts'),
          ),
        ],
      ),
    );
  }
}
