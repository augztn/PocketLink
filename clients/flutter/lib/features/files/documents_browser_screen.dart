import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/pocketlink_file_icon.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';

import '../../core/network/server_api.dart';
import 'file_manager_screen.dart';

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
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'csv', 'zip', '7z', 'rar', 'tar', 'gz',
  };
  static const _maxDirectories = 1800;
  static const _maxDepth = 18;
  static const _maxFiles = 10000;

  final _search = TextEditingController();
  List<_DocumentFile> _documents = const [];
  bool _loading = true;
  String? _error;
  int _scanned = 0;
  String _filter = 'all';
  bool _searchExpanded = false;
  bool _filterMenuOpen = false;
  String _sortBy = 'name';

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
    String extensionOf(_DocumentFile document) {
      final dot = document.entry.name.lastIndexOf('.');
      return dot < 0 ? '' : document.entry.name.substring(dot + 1).toLowerCase();
    }
    bool inCategory(_DocumentFile document) {
      final ext = extensionOf(document);
      switch (_filter) {
        case 'pdf': return ext == 'pdf';
        case 'office': return const {'doc','docx','xls','xlsx','ppt','pptx'}.contains(ext);
        case 'text': return const {'txt','md','csv'}.contains(ext);
        case 'archives': return const {'zip','7z','rar','tar','gz'}.contains(ext);
        default: return true;
      }
    }
    final filtered = _documents.where((document) =>
      inCategory(document) && (query.isEmpty ||
        document.entry.name.toLowerCase().contains(query) ||
        document.path.toLowerCase().contains(query))
    ).toList();
    filtered.sort((a, b) => _sortBy == 'newest'
      ? (DateTime.tryParse(b.entry.modified)?.compareTo(DateTime.tryParse(a.entry.modified) ?? DateTime.fromMillisecondsSinceEpoch(0)) ?? 0)
      : _sortBy == 'largest' ? b.entry.size.compareTo(a.entry.size)
      : a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    final counts = <String, int>{
      'all': _documents.length,
      'pdf': _documents.where((d) => extensionOf(d) == 'pdf').length,
      'office': _documents.where((d) => const {'doc','docx','xls','xlsx','ppt','pptx'}.contains(extensionOf(d))).length,
      'text': _documents.where((d) => const {'txt','md','csv'}.contains(extensionOf(d))).length,
      'archives': _documents.where((d) => const {'zip','7z','rar','tar','gz'}.contains(extensionOf(d))).length,
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? Colors.white : const Color(0xFF0F172A);
    final filterLabels = {'all':'All Docs','pdf':'PDF','office':'Office','text':'Text & Code','archives':'Archives'};
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        showHome: false,
        automaticallyImplyLeading: false,
        title: SmokedGlassPopoverMenu<String>(
          tooltip: 'Filter document types',
          onOpenChanged: (open) => setState(() => _filterMenuOpen = open),
          items: filterLabels.entries.map((entry) {
            final icon = switch (entry.key) {
              'pdf' => Icons.picture_as_pdf_rounded,
              'office' => Icons.article_rounded,
              'text' => Icons.text_snippet_rounded,
              'archives' => Icons.archive_rounded,
              _ => Icons.description_rounded,
            };
            return SmokedGlassPopoverMenuItem(
              value: entry.key,
              label: entry.value,
              icon: icon,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${counts[entry.key]}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                if (_filter == entry.key) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
              ]),
            );
          }).toList(),
          onSelected: (value) => setState(() => _filter = value),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text('Documents', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: titleColor))),
                  const SizedBox(width: 6),
                  AnimatedRotation(turns: _filterMenuOpen ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.keyboard_arrow_down_rounded)),
                ]),
                Text('${filtered.length} ${filtered.length == 1 ? 'document' : 'documents'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFFA1A7B3))),
              ]),
            ),

          ]),
        ),
        actions: [
          PocketLinkAppBarAction(label: 'Search documents', icon: Icons.search_rounded, onPressed: () => setState(() => _searchExpanded = !_searchExpanded)),
          PocketLinkAppBarAction(label: 'Sort by name', icon: Icons.sort_by_alpha_rounded,
            onPressed: () => setState(() => _sortBy = 'name')),
          PocketLinkAppBarAction(label: 'Sort by newest', icon: Icons.schedule_rounded,
            onPressed: () => setState(() => _sortBy = 'newest')),
          PocketLinkAppBarAction(label: 'Sort by largest', icon: Icons.storage_rounded,
            onPressed: () => setState(() => _sortBy = 'largest')),
          PocketLinkAppBarAction(label: 'Scan again', icon: Icons.refresh_rounded,
            onPressed: _loading ? null : () => _scan(refresh: true), dividerBefore: true),
        ],
      ),
      body: Column(children: [
        SizedBox(height: MediaQuery.paddingOf(context).top + kToolbarHeight + 4),
        if (_searchExpanded)
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CompactSearchField(controller: _search, hintText: 'Search documents', onChanged: (_) => setState(() {}))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text(
            '${filtered.length} ${filtered.length == 1 ? 'document' : 'documents'} • ${_loading ? 'Scanning $_scanned folders…' : '$_scanned folders scanned'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ))),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : filtered.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(borderRadius: BorderRadius.circular(22), child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45)),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_loading) const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2.5))
                      else Icon(Icons.description_outlined, size: 44, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(_loading ? 'Scanning storage for documents…' : 'No documents found', textAlign: TextAlign.center),
                      if (!_loading) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonal(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FileManagerScreen(api: widget.api))), child: const Text('Browse folders')),
                      ],
                    ]),
                  ),
                )),
              ))
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final document = filtered[index];
                  final extension = extensionOf(document).toUpperCase();
                  final colors = Theme.of(context).colorScheme;
                  return Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
                    ),
                    child: ListTile(
                      leading: PocketLinkFileIcon(name: document.entry.name, size: 44),
                      title: Text(document.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('$extension · ${_formatSize(document.entry.size)} · ${document.volume == null ? 'Internal storage' : 'USB / OTG'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(tooltip: 'Download original', onPressed: () => _download(document), icon: const Icon(Icons.download_rounded)),
                      onTap: () => _download(document),
                    ),
                  );
                },
              )),
      ]),
    );
  }
}
