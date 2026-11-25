import 'package:material_ui/material_ui.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/pocketlink_app_bar.dart';
import '../../../core/widgets/pocketlink_scaffold.dart';
import 'discover_cache.dart';
import 'discover_models.dart';
import 'discover_service.dart';
import 'discover_thumbnail_cache.dart';

class DiscoverMoodsScreen extends StatefulWidget {
  const DiscoverMoodsScreen({
    required this.service,
    required this.shimmerController,
    required this.onOpenTracks,
    required this.onPlay,
  });

  final DiscoverService service;
  final AnimationController shimmerController;
  final void Function(String title, List<DiscoverTrack> tracks) onOpenTracks;
  final void Function(DiscoverTrack track, List<DiscoverTrack> queue) onPlay;

  @override
  State<DiscoverMoodsScreen> createState() => DiscoverMoodsScreenState();
}

class DiscoverMoodsScreenState extends State<DiscoverMoodsScreen> {
  late Future<List<DiscoverMoodSection>> _sections;
  final TextEditingController _query = TextEditingController();
  bool _searching = false;
  bool _openingMood = false;
  List<DiscoverMoodSection>? _cachedSections;
  late final String _cacheKey;

  @override
  void initState() {
    super.initState();
    _cacheKey = 'moods:${AppSettings.instance.discoverRegion}';
    final cached = DiscoverCache.instance.read<List<DiscoverMoodSection>>(_cacheKey);
    _cachedSections = cached?.value;
    _sections = cached == null ? _loadSections() : Future.value(cached.value);
    if (cached != null && DiscoverCache.instance.isStale(cached)) {
      _sections = _loadSections();
    }
  }

  Future<List<DiscoverMoodSection>> _loadSections() async {
    final sections = await widget.service.moodsAndGenres();
    if (sections.isNotEmpty) {
      DiscoverCache.instance.write(_cacheKey, sections);
      _cachedSections = sections;
      return sections;
    }
    return _cachedSections ?? sections;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _skeletonBlock({
    required double width,
    required double height,
    double radius = 8,
  }) {
    return AnimatedBuilder(
      animation: widget.shimmerController,
      builder: (context, child) {
        final shift = -1.4 + (widget.shimmerController.value * 2.8);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(shift, 0),
            end: Alignment(shift + 1.2, 0),
            colors: const [
              Color(0xFF1A1A1E),
              Color(0xFF2A2A30),
              Color(0xFF1A1A1E),
            ],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1E),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _moodsSkeleton() {
    return SliverList(
      delegate: SliverChildListDelegate([
        for (var section = 0; section < 3; section++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: _skeletonBlock(
              width: 112 + section * 18,
              height: 13,
              radius: 6,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 76,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (_, __) => _skeletonBlock(
                width: double.infinity,
                height: 76,
                radius: 14,
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
      ]),
    );
  }

  Future<void> _submitSearch() async {
    final query = _query.text.trim();
    if (query.length < 2 || _searching) return;
    setState(() => _searching = true);
    try {
      final tracks = await widget.service.search(query);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onOpenTracks(query, tracks);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openMood(DiscoverMood mood) async {
    if (_searching || _openingMood) return;
    _openingMood = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _DiscoverCategoryScreen(
            mood: mood,
            service: widget.service,
            onPlay: widget.onPlay,
          ),
        ),
      );
    } finally {
      _openingMood = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        title: const Text('Search'),
        actions: const [],
      ),
      body: CustomScrollView(
        cacheExtent: 600,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 12, 20, 18),
              child: TextField(
                controller: _query,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                decoration: InputDecoration(
                  hintText: 'Songs, artists and albums',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _submitSearch,
                    icon: _searching
                        ? _skeletonBlock(width: 18, height: 18, radius: 9)
                        : const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .72),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          FutureBuilder<List<DiscoverMoodSection>>(
            future: _sections,
            initialData: _cachedSections,
            builder: (context, snapshot) {
              final sections = snapshot.data ?? _cachedSections;
              if (sections == null && snapshot.connectionState != ConnectionState.done) {
                return _moodsSkeleton();
              }
              if (sections == null || sections.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Moods & Moments are unavailable right now.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => setState(() => _sections = _loadSections()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildListDelegate([
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        primary: false,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: section.items.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 76,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (context, index) => _DiscoverMoodTile(
                          mood: section.items[index],
                          service: widget.service,
                          onTap: () => _openMood(section.items[index]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ]),
              );
            },
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: LayoutInsetsScope.of(context).bottomClearance + 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverCategoryScreen extends StatefulWidget {
  const _DiscoverCategoryScreen({
    required this.mood,
    required this.service,
    required this.onPlay,
  });

  final DiscoverMood mood;
  final DiscoverService service;
  final void Function(DiscoverTrack track, List<DiscoverTrack> queue) onPlay;

  @override
  State<_DiscoverCategoryScreen> createState() => _DiscoverCategoryScreenState();
}

class _DiscoverCategoryScreenState extends State<_DiscoverCategoryScreen> {
  List<DiscoverTrack> _tracks = const [];
  bool _loading = true;
  bool _usedSearchFallback = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _searchQuery {
    final title = widget.mood.title.trim();
    final musicSuffix = RegExp(r'\b(music|songs|playlist|playlists)\b', caseSensitive: false);
    return musicSuffix.hasMatch(title) ? title : '$title music';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _tracks = const [];
      _usedSearchFallback = false;
    });
    try {
      final mood = widget.mood;
      final hasBrowseData = mood.browseId.trim().isNotEmpty &&
          mood.params?.trim().isNotEmpty == true;
      List<DiscoverTrack> tracks = const [];
      if (hasBrowseData) {
        try {
          tracks = await widget.service.browseMood(mood);
        } catch (_) {
          // Fall through to a title search when the undocumented browse
          // endpoint rejects this category's browse payload.
        }
      }
      if (tracks.isEmpty) {
        _usedSearchFallback = true;
        tracks = await widget.service.search(_searchQuery, limit: 30);
      }
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        if (tracks.isEmpty) {
          _error = 'No results are available for ${widget.mood.title} right now.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load ${widget.mood.title}. Check your connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = widget.mood.stripeColor == 0
        ? theme.colorScheme.primary
        : Color(widget.mood.stripeColor);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        title: Text(widget.mood.title),
      ),
      body: CustomScrollView(
        cacheExtent: 600,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 18,
                20,
                12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.mood.title,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          _usedSearchFallback ? 'Discover search results' : 'YouTube Music category',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 12, width: 180,
                              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                            const SizedBox(height: 8),
                            Container(height: 9, width: 110,
                              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                childCount: 7,
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_off_rounded, size: 38),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.square(
                        dimension: 54,
                        child: track.thumbnailUrl.isEmpty
                            ? ColoredBox(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.music_note_rounded),
                              )
                            : DiscoverThumbnail(
                                url: DiscoverThumbnailCache.urlForSize(
                                  track.thumbnailUrl,
                                  160,
                                ),
                                cacheWidth: 160,
                                fallback: const ColoredBox(
                                  color: Color(0xFF1A1B20),
                                ),
                                errorFallback: ColoredBox(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.music_note_rounded),
                                ),
                              ),
                      ),
                    ),
                    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onPlay(track, _tracks),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: LayoutInsetsScope.of(context).bottomClearance + 24),
          ),
        ],
      ),
    );
  }
}

class _DiscoverMoodTile extends StatefulWidget {
  const _DiscoverMoodTile({
    required this.mood,
    required this.service,
    required this.onTap,
  });

  final DiscoverMood mood;
  final DiscoverService service;
  final VoidCallback onTap;

  @override
  State<_DiscoverMoodTile> createState() => _DiscoverMoodTileState();
}

class _DiscoverMoodTileState extends State<_DiscoverMoodTile> {
  late Future<List<DiscoverTrack>> _covers;

  String get _coverCacheKey =>
      'mood-cover:${AppSettings.instance.discoverRegion}:${widget.mood.browseId}:${widget.mood.params ?? ''}';

  Future<List<DiscoverTrack>> _loadCovers() async {
    final cached = DiscoverCache.instance.read<List<DiscoverTrack>>(_coverCacheKey);
    if (cached != null) {
      if (DiscoverCache.instance.isStale(cached)) {
        unawaited(widget.service.browseMood(widget.mood, limit: 2).then((tracks) {
          if (tracks.isNotEmpty) DiscoverCache.instance.write(_coverCacheKey, tracks);
        }).catchError((Object _) {}));
      }
      return cached.value;
    }
    final tracks = await widget.service.browseMood(widget.mood, limit: 2);
    if (tracks.isNotEmpty) DiscoverCache.instance.write(_coverCacheKey, tracks);
    return tracks;
  }

  @override
  void initState() {
    super.initState();
    _covers = _loadCovers();
  }

  @override
  void didUpdateWidget(covariant _DiscoverMoodTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood.browseId != widget.mood.browseId ||
        oldWidget.mood.params != widget.mood.params) {
      _covers = _loadCovers();
    }
  }

  Color _tint(int argb) {
    final source = Color(argb);
    return Color.lerp(source, const Color(0xFF777782), .42) ?? const Color(0xFF454550);
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint(widget.mood.stripeColor);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                Color.alphaBlend(tint.withValues(alpha: .55), const Color(0xFF24242A)),
                Color.alphaBlend(tint.withValues(alpha: .16), const Color(0xFF24242A)),
              ],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: 4,
                top: 5,
                bottom: 5,
                width: 76,
                child: FutureBuilder<List<DiscoverTrack>>(
                  future: _covers,
                  builder: (context, snapshot) {
                    final covers = snapshot.data ?? const <DiscoverTrack>[];
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (covers.length > 1)
                          Transform.translate(
                            offset: const Offset(-12, 2),
                            child: Transform.rotate(
                              angle: -.34,
                              child: _cover(covers[1].thumbnailUrl, 43),
                            ),
                          ),
                        if (covers.isNotEmpty)
                          Transform.translate(
                            offset: const Offset(10, 5),
                            child: Transform.rotate(
                              angle: -.08,
                              child: _cover(covers[0].thumbnailUrl, 48),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 66),
                  child: Text(
                    widget.mood.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(String url, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: size,
      child: url.isEmpty
          ? const ColoredBox(color: Color(0xFF393941))
          : DiscoverThumbnail(
              url: DiscoverThumbnailCache.urlForSize(
                url,
                size <= 60 ? 160 : 400,
              ),
              cacheWidth: size <= 60 ? 160 : 400,
              fallback: const ColoredBox(color: Color(0xFF1A1B20)),
              errorFallback: const ColoredBox(color: Color(0xFF393941)),
            ),
    ),
  );
}
