import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/pocketlink_file_icon.dart';

import '../../core/network/server_api.dart';

String canonicalDocumentPath(String path) {
  final normalized = path.replaceAll(String.fromCharCode(92), '/');
  final segments = <String>[];
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(part);
  }
  return segments.join('/');
}

class _DocumentFile {
  const _DocumentFile({
    required this.entry,
    required this.path,
    this.volume,
  });

  final FileEntry entry;
  final String path;
  final String? volume;
}

class DocumentsBrowserScreen extends StatefulWidget {
  const DocumentsBrowserScreen({required this.api, super.key});

  final ServerApi api;

  @override
  State<DocumentsBrowserScreen> createState() => _DocumentsBrowserScreenState();
}

class _DocumentsBrowserScreenState extends State<DocumentsBrowserScreen> {
  static const _extensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'txt', 'md', 'csv',
  };
  static const _maxDirectories = 1800;
  static const _maxDepth = 18;
  static const _maxFiles = 10000;

  final _search = TextEditingController();
  List<_DocumentFile> _documents = const [];
  bool _loading = true;
  String? _error;
  int _scanned = 0;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan({bool refresh = false}) async {
    if (refresh) widget.api.invalidateDirectoryCache();
    setState(() {
      _loading = true;
      _error = null;
      _documents = const [];
      _scanned = 0;
    });
    final found = <_DocumentFile>[];
    final seenDocumentPaths = <String>{};
    final pending = <({String path, String? volume, int depth})>[];
    final visited = <String>{};
    try {
      try {
        final volumes = await widget.api.listStorageVolumes();
        for (final volume in volumes.where((item) => item.available)) {
          pending.add((path: '', volume: volume.id, depth: 0));
        }
      } catch (_) {
        // Internal storage remains searchable if volume discovery is unavailable.
      }
      pending.add((path: '', volume: null, depth: 0));

      var cursor = 0;
      while (cursor < pending.length && visited.length < _maxDirectories && found.length < _maxFiles) {
        final current = pending[cursor++];
        final key = '${current.volume ?? 'internal'}:${current.path}';
        if (!visited.add(key)) continue;
        try {
          final listing = current.volume == null
              ? await widget.api.listDirectory(current.path)
              : await widget.api.listStorageDirectory(current.volume!, current.path);
          _scanned++;
          for (final item in listing.items) {
            if (found.length >= _maxFiles) break;
            final path = current.path.isEmpty ? item.name : '${current.path}/${item.name}';
            if (item.isDirectory) {
              if (current.depth < _maxDepth) {
                pending.add((path: path, volume: current.volume, depth: current.depth + 1));
              }
            } else {
              final dot = item.name.lastIndexOf('.');
              final extension = dot < 0 ? '' : item.name.substring(dot + 1).toLowerCase();
              if (_extensions.contains(extension)) {
                final canonicalPath = canonicalDocumentPath(path);
                final sourceKey = current.volume ?? 'internal';
                if (seenDocumentPaths.add('$sourceKey:$canonicalPath')) {
                  found.add(_DocumentFile(entry: item, path: canonicalPath, volume: current.volume));
                }
              }
            }
          }
        } catch (_) {
          // A disconnected or permission-restricted folder does not stop other roots.
        }
        if (mounted && cursor % 12 == 0) {
          setState(() => _documents = List.unmodifiable(found));
        }
      }
      found.sort((a, b) => a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    } catch (error) {
      _error = 'Could not scan documents: $error';
    } finally {
      if (mounted) {
        setState(() {
          _documents = List.unmodifiable(found);
          _loading = false;
        });
      }
    }
  }

  Future<void> _download(_DocumentFile document) async {
    try {
      final bytes = document.volume == null
          ? await widget.api.downloadFile(document.path)
          : await widget.api.downloadStorageFile(document.volume!, document.path);
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save document',
        fileName: document.entry.name,
        bytes: bytes,
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download this document.')),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final items = _documents.where((document) =>
      query.isEmpty ||
      document.entry.name.toLowerCase().contains(query) ||
      document.path.toLowerCase().contains(query)
    ).toList(growable: false);

    return Scaffold(
      appBar: PocketLinkAppBar(
        title: const Text('Documents', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PocketLinkAppBarAction(label: 'Scan again', icon: Icons.refresh_rounded, onPressed: _loading ? null : () => _scan(refresh: true)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: CompactSearchField(
              controller: _search,
              hintText: 'Search documents',
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('${items.length} ${items.length == 1 ? 'document' : 'documents'}',
                  style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  _loading ? 'Scanning $_scanned folders…' : '$_scanned folders scanned',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.description_outlined, size: 48,
                                color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 12),
                              Text(
                                _loading ? 'Scanning storage for documents…' : 'No documents found',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(12, 8, 12,
                          104 + MediaQuery.paddingOf(context).bottom),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final document = items[index];
                          final extension = document.entry.name.split('.').last.toUpperCase();
                           final colors = Theme.of(context).colorScheme;
                           return Container(
                             decoration: BoxDecoration(
                               color: colors.surfaceContainerLow,
                               borderRadius: BorderRadius.circular(18),
                               border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.62)),
                            ),
                            child: ListTile(
                              leading: PocketLinkFileIcon(
                                 name: document.entry.name,
                                 size: 44,
                               ),
                              title: Text(document.entry.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '$extension · ${_formatSize(document.entry.size)} · ${document.volume == null ? 'Internal storage' : 'USB / OTG'}',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Download original',
                                onPressed: () => _download(document),
                                icon: const Icon(Icons.download_rounded),
                              ),
                              onTap: () => _download(document),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
