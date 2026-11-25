import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';

class MediaBrowserFilterSheet extends StatefulWidget {
  const MediaBrowserFilterSheet({
    required this.volumes,
    required this.initialVolume,
    required this.initialSort,
    super.key,
  });

  final List<StorageVolume> volumes;
  final String? initialVolume;
  final String initialSort;

  @override
  State<MediaBrowserFilterSheet> createState() =>
      _MediaBrowserFilterSheetState();
}

class _MediaBrowserFilterSheetState extends State<MediaBrowserFilterSheet> {
  late String? _volume = widget.initialVolume;
  late String _sort = widget.initialSort;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xEE17191F)
                  : const Color(0xEEF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: isDark ? 0.14 : 0.55,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter & sort',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 18),
                const Text(
                  'STORAGE SOURCE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    color: Color(0xFFA1A7B3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _volume,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All storage'),
                    ),
                    const DropdownMenuItem<String?>(
                      value: 'internal',
                      child: Text('Internal storage'),
                    ),
                    ...widget.volumes
                        .where((volume) => volume.available)
                        .map((volume) => DropdownMenuItem<String?>(
                              value: volume.id,
                              child: Text(volume.name),
                            )),
                  ],
                  onChanged: (value) => setState(() => _volume = value),
                ),
                const SizedBox(height: 18),
                const Text(
                  'SORT ORDER',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    color: Color(0xFFA1A7B3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in [
                      ('name', 'Name'),
                      ('newest', 'Newest'),
                      ('largest', 'Largest'),
                    ])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: _sort == option.$1,
                        onSelected: (_) =>
                            setState(() => _sort = option.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      (volume: _volume, sort: _sort),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
