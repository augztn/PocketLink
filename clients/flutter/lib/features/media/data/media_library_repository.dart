import 'package:dio/dio.dart';

import '../../../core/network/server_api.dart';
import '../media_library_catalog.dart';

/// Result of reading one media category from the host's indexed library.
class MediaLibraryResult {
  const MediaLibraryResult({required this.items, required this.status});

  final List<MediaFileItem> items;
  final MediaIndexStatus status;
}

/// Owns indexed media pagination and conversion from host DTOs to catalog items.
///
/// Legacy directory traversal remains a separate fallback in the screen until
/// it can be extracted and tested independently.
class MediaLibraryRepository {
  const MediaLibraryRepository({
    required this.api,
    required this.type,
  });

  final ServerApi api;
  final MediaLibraryType type;

  Future<MediaLibraryResult> readIndexedMedia({
    String query = '',
    bool Function()? shouldContinue,
  }) async {
    final category = type == MediaLibraryType.music ? 'music' : 'video';
    final found = <MediaFileItem>[];
    var offset = 0;
    var status = const MediaIndexStatus(
      state: 'idle',
      scanned: 0,
      skipped: 0,
      lastCompletedAt: 0,
      fileCount: 0,
      mediaCount: 0,
    );

    do {
      final page = await api.indexedMedia(
        category,
        // The host index only searches file paths/names. Music queries must
        // run after embedded tags are attached so title/artist/album matches
        // are not discarded before metadata lookup.
        query: type == MediaLibraryType.music ? '' : query,
        limit: _pageSize,
        offset: offset,
      );
      status = page.status;
      if (shouldContinue != null && !shouldContinue()) break;

      found.addAll(
        page.items
            .where((item) => MediaLibraryCatalog.isMedia(
                  item.toFileEntry(),
                  type: type,
                  mime: item.mime,
                ))
            .map((item) {
              return MediaFileItem(
                entry: item.toFileEntry(),
                path: item.path,
                volume: item.volume == 'internal' ? null : item.volume,
                title: item.title,
                artist: item.artist,
                album: item.album,
                durationMs: item.durationMs,
              );
            }),
      );

      offset += page.items.length;
      if (page.items.length < _pageSize) break;
    } while (true);

    // Keep this indexed-media read self-contained. The optional legacy
    // /api/music/library endpoint is absent on current PocketLink hosts and
    // caused a guaranteed 404 during Discover enrichment.
    final normalizedQuery = query.trim().toLowerCase();
    final results = normalizedQuery.isEmpty
        ? found
        : found.where((item) =>
            item.entry.name.toLowerCase().contains(normalizedQuery) ||
            item.path.toLowerCase().contains(normalizedQuery) ||
            (item.title?.toLowerCase().contains(normalizedQuery) ?? false) ||
            (item.artist?.toLowerCase().contains(normalizedQuery) ?? false) ||
            (item.album?.toLowerCase().contains(normalizedQuery) ?? false),
          ).toList(growable: false);

    results.sort((a, b) =>
        a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));

    return MediaLibraryResult(
      items: List.unmodifiable(results),
      status: status,
    );
  }

  static const _pageSize = 500;
}
