import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/server_api.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import 'data/media_library_repository.dart';
import 'media_library_catalog.dart';

class DuplicateMusicScreen extends StatefulWidget {
  const DuplicateMusicScreen({required this.api, super.key});
  final ServerApi api;
  @override
  State<DuplicateMusicScreen> createState() => _DuplicateMusicScreenState();
}

class _DuplicateMusicScreenState extends State<DuplicateMusicScreen> {
  static const muted = Color(0xFF9295A0);
  CancelToken? _cancel;
  bool _busy = false;
  int _done = 0, _total = 0, _skipped = 0;
  String? _error;
  List<List<MediaFileItem>> _groups = const [];

  @override
  void dispose() {
    _cancel?.cancel('Screen closed');
    super.dispose();
  }

  Future<void> _scan({bool rehash = false}) async {
    if (_busy) return;
    final token = CancelToken();
    setState(() {
      _busy = true; _done = 0; _total = 0; _skipped = 0;
      _error = null; _groups = const []; _cancel = token;
    });
    try {
      final result = await MediaLibraryRepository(
        api: widget.api, type: MediaLibraryType.music,
      ).readIndexedMedia(shouldContinue: () => mounted && !token.isCancelled);
      if (!mounted || token.isCancelled) return;
      final sized = <int, List<MediaFileItem>>{};
      for (final item in result.items) {
        sized.putIfAbsent(item.entry.size, () => []).add(item);
      }
      final candidates = sized.values.where((items) => items.length > 1)
          .expand((items) => items).toList(growable: false);
      setState(() => _total = candidates.length);
      final prefs = await SharedPreferences.getInstance();
      final digests = <String, List<MediaFileItem>>{};
      var done = 0, skipped = 0;
      for (final item in candidates) {
        if (!mounted || token.isCancelled) break;
        try {
          final digest = await _digest(item, prefs, token, rehash);
          if (digest == null) { skipped++; }
          else { digests.putIfAbsent(digest, () => []).add(item); }
        } on DioException {
          if (token.isCancelled) break;
          skipped++;
        } catch (_) { skipped++; }
        done++;
        if (mounted) setState(() { _done = done; _skipped = skipped; });
      }
      if (!mounted || token.isCancelled) return;
      final groups = digests.values.where((items) => items.length > 1)
          .map((items) => List<MediaFileItem>.unmodifiable(items)).toList()
        ..sort((a, b) => b.first.entry.size.compareTo(a.first.entry.size));
      setState(() => _groups = List.unmodifiable(groups));
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = 'Could not scan the indexed music library.');
      }
    } finally {
      if (mounted) setState(() { _busy = false; _cancel = null; });
    }
  }

  Future<String?> _digest(MediaFileItem item, SharedPreferences prefs,
      CancelToken token, bool rehash) async {
    final id = sha256.convert(utf8.encode(
      widget.api.baseUrl + '|' + (item.volume ?? 'internal') + '|' + item.path,
    )).toString();
    final key = 'pocketlink.duplicate.sha256.v1.' + id;
    final stamp = item.entry.size.toString() + '|' + item.entry.modified;
    if (!rehash) {
      final cached = prefs.getString(key);
      if (cached != null && cached.startsWith(stamp + '|')) {
        final value = cached.substring(stamp.length + 1);
        if (RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) return value;
      }
    }
    final response = await widget.api.openDownloadStream(
      path: item.path, volume: item.volume, cancelToken: token,
    );
    final body = response.data;
    if (body == null) return null;
    final value = (await sha256.bind(body.stream).first).toString();
    await prefs.setString(key, stamp + '|' + value);
    return value;
  }

  String _size(int bytes) {
    if (bytes < 1024) return bytes.toString() + ' B';
    if (bytes < 1048576) return (bytes / 1024).toStringAsFixed(1) + ' KB';
    if (bytes < 1073741824) return (bytes / 1048576).toStringAsFixed(1) + ' MB';
    return (bytes / 1073741824).toStringAsFixed(2) + ' GB';
  }

  @override
  Widget build(BuildContext context) {
    final copies = _groups.fold<int>(0, (n, group) => n + group.length - 1);
    final layout = LayoutInsetsScope.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PocketLinkAppBar(
        feathered: true, showHome: false, title: const Text('Duplicate music'),
        leading: IconButton(
          tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        leadingWidth: 56,
        actions: [PocketLinkAppBarAction(
          label: 'Rehash all candidates', icon: Icons.refresh_rounded,
          onPressed: _busy ? null : () => _scan(rehash: true),
        )],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, layout.topClearance + 12, 16, layout.bottomClearance + 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF161618), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Find byte-identical tracks',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('SHA-256 confirms exact file matches. Similar names or audio are not treated as duplicates.',
                style: TextStyle(color: muted, height: 1.4)),
              const SizedBox(height: 16),
              if (_busy) ...[
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                const SizedBox(height: 8),
                Text('Hashed ' + _done.toString() + ' of ' + _total.toString() +
                    ' candidates · ' + _skipped.toString() + ' unavailable',
                  style: const TextStyle(color: muted, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _busy ? () => _cancel?.cancel('Cancelled') : () => _scan(),
                icon: Icon(_busy ? Icons.stop_rounded : Icons.search_rounded),
                label: Text(_busy ? 'Cancel scan' : 'Scan for duplicates'),
              )),
            ]),
          ),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
          if (!_busy && _groups.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(copies.toString() + ' duplicate copies in ' + _groups.length.toString() + ' groups',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('No files have been changed.', style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 12),
            for (final group in _groups)
              Container(
                margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161618), borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_size(group.first.entry.size),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  for (final item in group)
                    ListTile(
                      dense: true, contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.audio_file_rounded, color: muted),
                      title: Text(item.title?.trim().isNotEmpty == true ? item.title! : item.entry.name,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text((item.artist?.trim().isNotEmpty == true ? item.artist! + ' · ' : '') +
                          (item.volume ?? 'Internal storage') + ' · ' + item.path,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 11)),
                    ),
                ]),
              ),
          ],
          if (!_busy && _error == null && _total > 0 && _groups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: Text('No byte-identical music files found.', style: TextStyle(color: muted))),
            ),
          if (!_busy && _error == null && _total == 0 && _groups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: Text('Scan the indexed music library to check for duplicates.',
                textAlign: TextAlign.center, style: TextStyle(color: muted))),
            ),
        ],
      ),
    );
  }
}
