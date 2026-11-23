import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/server_api.dart';
import '../../core/network/server_api_models.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../media/data/media_library_repository.dart';
import '../media/media_library_catalog.dart';
import '../media/now_playing_overlay_controller.dart';
import '../media/persistent_audio_player.dart';
import 'discover_models.dart';
import 'discover_service.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({required this.api, super.key});

  final ServerApi api;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final DiscoverService _service = DiscoverService();
  final TextEditingController _searchController = TextEditingController();
  List<DiscoverTrack> _tracks = const [];
  List<IndexedFile> _localLibrary = const [];
  bool _loading = false;
  bool _loadingLibrary = false;
  String? _error;
  String _sectionTitle = 'Popular in India';

  @override
  void initState() {
    super.initState();
    _loadLocalLibrary();
    _search('top songs India');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalLibrary() async {
    if (_loadingLibrary) return;
    _loadingLibrary = true;
    try {
      final result = await MediaLibraryRepository(
        api: widget.api,
        type: MediaLibraryType.music,
      ).readIndexedMedia();
      if (!mounted) return;
      setState(() {
        _localLibrary = result.items.map((item) => IndexedFile(
          volume: item.volume ?? 'internal',
          path: item.path,
          name: item.entry.name,
          type: item.entry.type,
          size: item.entry.size,
          modified: item.entry.modified,
          mime: '',
          category: 'music',
        )).toList(growable: false);
      });
    } catch (_) {
      // Discovery remains usable when the host library is temporarily offline.
    } finally {
      _loadingLibrary = false;
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2 || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _sectionTitle = query.trim();
    });
    try {
      final results = await _service.search(query);
      if (!mounted) return;
      setState(() {
        _tracks = results;
        if (results.isEmpty) _error = 'No tracks found. Try another search.';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'Discover is unavailable on this device.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load Discover results. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(DiscoverTrack track) async {
    final local = DiscoverService.findLocalLosslessMatch(track, _localLibrary);
    try {
      final item = local != null
          ? MediaQueueItem(
              title: track.title,
              path: local.path,
              volume: local.volume == 'internal' ? null : local.volume,
              size: local.size,
            )
          : await _remoteQueueItem(track);
      await PersistentAudioPlayer.instance.openQueue(
        api: widget.api,
        queue: [item],
        initialIndex: 0,
        isMusic: true,
      );
      NowPlayingOverlayController.open();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is PlatformException
            ? error.message ?? 'Could not resolve this track.'
            : 'Could not start playback. Try again later.')),
      );
    }
  }

  Future<MediaQueueItem> _remoteQueueItem(DiscoverTrack track) async {
    final stream = await _service.resolve(track);
    return MediaQueueItem(
      title: track.title,
      path: track.videoId,
      streamUrl: stream.url,
      httpHeaders: {
        'User-Agent': stream.userAgent,
        'Accept': '*/*',
      },
    );
  }

  Future<void> _showLyrics(DiscoverTrack track) async {
    try {
      final lyrics = await _service.lyrics(track);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(track.artist, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text(lyrics == null
                          ? 'Lyrics not found'
                          : '${lyrics.isSynced ? 'Synced lyrics' : 'Plain lyrics'} · ${lyrics.source}',
                        style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: lyrics == null
                      ? const Center(child: Text('No matching lyrics were found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: lyrics.lines.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Text(
                              lyrics.lines[index].text,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not retrieve lyrics.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        showHome: false,
        title: const Text('Discover'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search songs, artists and albums',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: () => _search(_searchController.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (_loadingLibrary)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ),
            if (_loading && _tracks.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _tracks.isEmpty)
              Expanded(child: Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              )))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _search(_searchController.text.isEmpty
                      ? 'top songs India'
                      : _searchController.text),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: _tracks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      final local = DiscoverService.findLocalLosslessMatch(track, _localLibrary);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: track.thumbnailUrl.isEmpty
                              ? Container(
                                  width: 52,
                                  height: 52,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.music_note_rounded),
                                )
                              : Image.network(
                                  track.thumbnailUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 52,
                                    height: 52,
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.music_note_rounded),
                                  ),
                                ),
                        ),
                        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${track.artist}${track.durationText.isEmpty ? '' : ' · ${track.durationText}'}${local == null ? '' : ' · ${local.name.split('.').last.toUpperCase()} LOSSLESS'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Track options',
                          onSelected: (value) {
                            if (value == 'lyrics') _showLyrics(track);
                            if (value == 'play') _play(track);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'play', child: Text('Play')),
                            PopupMenuItem(value: 'lyrics', child: Text('Lyrics')),
                          ],
                        ),
                        onTap: () => _play(track),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
