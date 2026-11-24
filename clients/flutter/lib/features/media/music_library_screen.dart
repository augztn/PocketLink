import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/network/server_api.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../downloads/download_manager_service.dart';
import 'data/media_library_repository.dart';
import 'media_browser_screen.dart';
import 'media_library_catalog.dart';

const _libraryCanvas = Color(0xFF000000);
const _libraryCard = Color(0xFF15161B);
const _libraryCardAlt = Color(0xFF1E1F24);
const _libraryAccent = Color(0xFFB8C4FF);

enum _LibraryScope { all, local, cached }

class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({required this.api, this.onOpenGenres, this.onOpenImported, super.key});

  final ServerApi api;
  final VoidCallback? onOpenGenres;
  final VoidCallback? onOpenImported;

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen> {
  final TextEditingController _search = TextEditingController();
  List<MediaFileItem> _tracks = const [];
  int _cachedCount = 0;
  bool _loading = true;
  String? _error;
  _LibraryScope _scope = _LibraryScope.all;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(DownloadManagerService.instance.initialize().then((_) {
      if (mounted) setState(() => _cachedCount = _completedAudioDownloads());
    }).catchError((Object _) {}));
    DownloadManagerService.instance.addListener(_downloadsChanged);
  }

  @override
  void dispose() {
    DownloadManagerService.instance.removeListener(_downloadsChanged);
    _search.dispose();
    super.dispose();
  }

  void _downloadsChanged() {
    if (mounted) setState(() => _cachedCount = _completedAudioDownloads());
  }

  int _completedAudioDownloads() {
    const extensions = {'mp3', 'flac', 'm4a', 'wav', 'ogg', 'aac', 'opus', 'alac', 'aiff', 'ape', 'wv', 'dsf', 'dff'};
    return DownloadManagerService.instance.tasks.where((task) {
      final dot = task.fileName.lastIndexOf('.');
      final extension = dot < 0 ? '' : task.fileName.substring(dot + 1).toLowerCase();
      return task.status == DownloadStatus.completed && extensions.contains(extension);
    }).length;
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await MediaLibraryRepository(api: widget.api, type: MediaLibraryType.music).readIndexedMedia(
        shouldContinue: () => mounted,
      );
      if (!mounted) return;
      setState(() { _tracks = result.items; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not read the indexed music library.'; });
    }
  }

  List<MediaFileItem> get _visibleTracks {
    final query = _search.text.trim().toLowerCase();
    final items = _tracks.where((item) {
      final isCached = item.volume == 'cache';
      if (_scope == _LibraryScope.cached && !isCached) return false;
      if (_scope == _LibraryScope.local && isCached) return false;
      if (query.isEmpty) return true;
      return item.entry.name.toLowerCase().contains(query) || item.path.toLowerCase().contains(query);
    }).toList(growable: false);
    return items;
  }

  int get _songCount => switch (_scope) {
    _LibraryScope.all => _tracks.length + _cachedCount,
    _LibraryScope.local => _tracks.where((item) => item.volume != 'cache').length,
    _LibraryScope.cached => _cachedCount,
  };

  int get _recentCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return _tracks.where((item) {
      final modified = DateTime.tryParse(item.entry.modified);
      return modified != null && modified.isAfter(cutoff) &&
          (_scope != _LibraryScope.cached);
    }).length;
  }

  Future<void> _openSongs({String view = 'all', String sort = 'name'}) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MediaBrowserScreen(
        api: widget.api,
        type: MediaLibraryType.music,
        initialView: view,
        initialSortBy: sort,
      ),
    ));
  }

  void _unavailable(String collection) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(collection + ' metadata is not available in the current indexed library.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = LayoutInsetsScope.of(context);
    final media = MediaQuery.of(context);
    final bottom = layout.bottomClearance + 24;
    final songs = _songCount;
    final recent = _recentCount;
    final scopeLabel = switch (_scope) {
      _LibraryScope.all => 'All',
      _LibraryScope.local => 'Local & downloaded',
      _LibraryScope.cached => 'Cached',
    };

    return Scaffold(
      backgroundColor: _libraryCanvas,
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        showHome: false,
        title: const Text('Library'),
        actions: [
          PocketLinkAppBarAction(label: 'Refresh library', icon: Icons.refresh_rounded, onPressed: _loading ? null : _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16 + media.padding.left, layout.topClearance + 12, 16 + media.padding.right, bottom),
          children: [
            SizedBox(
              height: 46,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search your library',
                  hintStyle: const TextStyle(color: Color(0xFF9295A0), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9295A0), size: 20),
                  filled: true,
                  fillColor: _libraryCardAlt,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: _libraryAccent, width: 1)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: _libraryCardAlt, borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                _scopeSegment('All', _LibraryScope.all),
                _scopeSegment('Local & downloaded', _LibraryScope.local),
                _scopeSegment('Cached', _LibraryScope.cached),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _quickChip('History', Icons.history_rounded, () => _unavailable('Listening history')),
              const SizedBox(width: 8),
              _quickChip('Genres', Icons.category_rounded, widget.onOpenGenres ?? () => _unavailable('Genre')),
              const SizedBox(width: 8),
              _quickChip('Imported', Icons.playlist_add_rounded, widget.onOpenImported ?? () => _unavailable('Imported playlist')),
            ]),
            const SizedBox(height: 16),
            if (_error != null)
              _messageCard(_error!, Icons.cloud_off_rounded)
            else ...[
              Row(children: [
                const Text('YOUR COLLECTION', style: TextStyle(color: _libraryAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const Spacer(),
                if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                Text(scopeLabel, style: const TextStyle(color: Color(0xFF858994), fontSize: 11)),
              ]),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  LibraryBentoCard(title: 'Songs', count: songs, icon: Icons.music_note_rounded, art: _BentoArt.album, onTap: () => _openSongs()),
                  LibraryBentoCard(title: 'Playlists', count: 0, icon: Icons.queue_music_rounded, art: _BentoArt.stack, onTap: () => _unavailable('Playlist')),
                  LibraryBentoCard(title: 'Albums', count: 0, icon: Icons.album_rounded, art: _BentoArt.album, onTap: () => _unavailable('Album')),
                  LibraryBentoCard(title: 'Artists', count: 0, icon: Icons.person_rounded, art: _BentoArt.artists, onTap: () => _unavailable('Artist')),
                ],
              ),
              const SizedBox(height: 12),
              LibraryBentoCard(title: 'Recently added', count: recent, icon: Icons.fiber_new_rounded, wide: true, art: _BentoArt.stack, onTap: () => _openSongs(sort: 'newest')),
              const SizedBox(height: 12),
              LibraryBentoCard(title: 'Liked', count: 0, icon: Icons.favorite_rounded, wide: true, art: _BentoArt.liked, onTap: () => _openSongs(view: 'favorites')),
              if (_scope == _LibraryScope.cached && _cachedCount > 0) ...[
                const SizedBox(height: 12),
                _messageCard('Cached audio downloads are counted here. Open Downloads to manage or play them.', Icons.download_done_rounded),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _scopeSegment(String label, _LibraryScope value) {
    final selected = _scope == value;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _scope = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: selected ? const Color(0xFF343846) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.center,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : const Color(0xFF9A9DA7), fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    ));
  }

  Widget _quickChip(String label, IconData icon, VoidCallback onTap) => Expanded(child: Material(
    color: const Color(0xFF181A21),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: _libraryAccent.withValues(alpha: 0.16))),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: _libraryAccent),
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ),
    ),
  ));

  Widget _messageCard(String message, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _libraryCard, borderRadius: BorderRadius.circular(18)),
    child: Row(children: [Icon(icon, color: _libraryAccent), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFAEB1BA), fontSize: 12)))]),
  );
}

enum _BentoArt { album, stack, artists, liked }

class LibraryBentoCard extends StatelessWidget {
  const LibraryBentoCard({required this.title, required this.count, required this.icon, required this.art, required this.onTap, this.wide = false, super.key});

  final String title;
  final int count;
  final IconData icon;
  final _BentoArt art;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _libraryCard,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          Positioned(left: 14, top: 14, right: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(count.toString(), style: const TextStyle(color: Color(0xFF8C909B), fontSize: 31, height: 1, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          ])),
          if (count == 0)
            Positioned(right: 8, bottom: 0, child: Icon(icon, size: wide ? 76 : 68, color: Colors.white.withValues(alpha: 0.08)))
          else
            _artwork(),
          if (art == _BentoArt.liked)
            Positioned(right: 12, bottom: 12, child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
              child: const Icon(Icons.favorite_rounded, color: Color(0xFFE8A9BE), size: 17),
            )),
        ]),
      ),
    );
  }

  Widget _artwork() {
    final size = wide ? 76.0 : 66.0;
    if (art == _BentoArt.artists) {
      return Positioned(right: 12, bottom: 10, child: SizedBox(width: size + 28, height: size, child: Stack(children: [
        Positioned(right: 30, child: _artTile(size, const Color(0xFF655A8F), Icons.person_rounded, true)),
        Positioned(right: 0, child: _artTile(size, const Color(0xFF3E6874), Icons.person_rounded, true)),
      ])));
    }
    return Positioned(right: 10, bottom: 8, child: SizedBox(width: size + 44, height: size + 18, child: Stack(children: [
      Positioned(right: 38, bottom: 2, child: Transform.rotate(angle: -0.22, child: _artTile(size, const Color(0xFF394A76), Icons.music_note_rounded))),
      Positioned(right: 18, bottom: 0, child: Transform.rotate(angle: -0.08, child: _artTile(size, const Color(0xFF6A527E), Icons.album_rounded))),
      Positioned(right: 0, bottom: 2, child: Transform.rotate(angle: 0.12, child: _artTile(size, const Color(0xFF3D6A67), Icons.graphic_eq_rounded))),
    ])));
  }

  Widget _artTile(double size, Color color, IconData icon, [bool circle = false]) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: color, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : BorderRadius.circular(13), border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1)),
    child: Icon(icon, color: Colors.white.withValues(alpha: 0.72), size: size * 0.34),
  );
}
