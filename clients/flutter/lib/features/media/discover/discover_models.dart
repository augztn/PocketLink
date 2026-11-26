class DiscoverTrack {
  const DiscoverTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.durationText = '',
    this.thumbnailUrl = '',
  });

  final String videoId;
  final String title;
  final String artist;
  final String durationText;
  final String thumbnailUrl;

  factory DiscoverTrack.fromJson(Map<String, dynamic> json) => DiscoverTrack(
        videoId: json['videoId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? 'Discover',
        durationText: json['durationText']?.toString() ?? '',
        thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
      );
}


class DiscoverHomeShelf {
  const DiscoverHomeShelf({required this.title, required this.tracks});

  final String title;
  final List<DiscoverTrack> tracks;

  factory DiscoverHomeShelf.fromJson(Map<String, dynamic> json) =>
      DiscoverHomeShelf(
        title: json['title']?.toString() ?? '',
        tracks: (json['tracks'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => DiscoverTrack.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .where((track) => track.videoId.isNotEmpty)
            .toList(growable: false),
      );
}

class DiscoverHomeFeed {
  const DiscoverHomeFeed({
    required this.shelves,
    this.continuation = '',
  });

  final List<DiscoverHomeShelf> shelves;
  final String continuation;

  factory DiscoverHomeFeed.fromJson(Map<String, dynamic> json) =>
      DiscoverHomeFeed(
        shelves: (json['shelves'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => DiscoverHomeShelf.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .where((shelf) => shelf.title.isNotEmpty && shelf.tracks.isNotEmpty)
            .toList(growable: false),
        continuation: json['continuation']?.toString() ?? '',
      );
}


/// Appends a continuation page without repeating a track across Home shelves.
List<DiscoverHomeShelf> mergeDiscoverHomeShelves(
  List<DiscoverHomeShelf> current,
  List<DiscoverHomeShelf> incoming,
) {
  final seenVideoIds = <String>{};
  final merged = current.map((shelf) {
    final tracks = shelf.tracks
        .where((track) => seenVideoIds.add(track.videoId))
        .toList(growable: false);
    return DiscoverHomeShelf(title: shelf.title, tracks: tracks);
  }).toList();

  for (final shelf in incoming) {
    final freshTracks = shelf.tracks
        .where((track) => seenVideoIds.add(track.videoId))
        .toList(growable: false);
    if (freshTracks.isEmpty) continue;
    final index = merged.indexWhere(
      (item) => item.title.toLowerCase() == shelf.title.toLowerCase(),
    );
    if (index < 0) {
      merged.add(DiscoverHomeShelf(title: shelf.title, tracks: freshTracks));
    } else {
      merged[index] = DiscoverHomeShelf(
        title: merged[index].title,
        tracks: [...merged[index].tracks, ...freshTracks],
      );
    }
  }
  return List.unmodifiable(merged);
}


class DiscoverMoodSection {
  const DiscoverMoodSection({required this.title, required this.items});
  final String title;
  final List<DiscoverMood> items;

  factory DiscoverMoodSection.fromJson(Map<String, dynamic> json) => DiscoverMoodSection(
    title: json['title']?.toString() ?? '',
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => DiscoverMood.fromJson(item.map((key, value) => MapEntry(key.toString(), value))))
        .toList(growable: false),
  );
}

class DiscoverMood {
  const DiscoverMood({
    required this.title,
    required this.browseId,
    this.params,
    this.stripeColor = 0,
  });
  final String title;
  final String browseId;
  final String? params;
  final int stripeColor;

  factory DiscoverMood.fromJson(Map<String, dynamic> json) => DiscoverMood(
    title: json['title']?.toString() ?? '',
    browseId: json['browseId']?.toString() ?? '',
    params: json['params']?.toString(),
    stripeColor: (json['stripeColor'] as num?)?.toInt() ?? 0,
  );
}

class DiscoverLyricsLine {
  const DiscoverLyricsLine({required this.timeMs, required this.text});

  final int timeMs;
  final String text;
}

class DiscoverLyrics {
  const DiscoverLyrics({
    required this.lines,
    required this.isSynced,
    required this.source,
  });

  final List<DiscoverLyricsLine> lines;
  final bool isSynced;
  final String source;
}

class DiscoverResolvedStream {
  const DiscoverResolvedStream({
    required this.url,
    required this.mimeType,
    required this.userAgent,
    this.bitrateBps = 0,
    this.resolver = '',
    this.codec = '',
    this.quality = 'best_available',
    this.qualityFallbackReason = '',
    this.audioOnly = true,
  });

  final String url;
  final String mimeType;
  final String userAgent;
  final int bitrateBps;
  final String resolver;
  final String codec;
  final String quality;
  final String qualityFallbackReason;
  final bool audioOnly;

  factory DiscoverResolvedStream.fromJson(Map<String, dynamic> json) =>
      DiscoverResolvedStream(
        url: json['url']?.toString() ?? '',
        mimeType: json['mimeType']?.toString() ?? 'audio/webm',
        userAgent: json['userAgent']?.toString() ?? '',
        bitrateBps: (json['bitrateBps'] as num?)?.toInt() ?? 0,
        resolver: json['resolver']?.toString() ?? '',
        codec: json['codec']?.toString() ?? '',
        quality: json['quality']?.toString() ?? 'best_available',
        qualityFallbackReason: json['qualityFallbackReason']?.toString() ?? '',
        audioOnly: json['audioOnly'] as bool? ?? true,
      );
}
