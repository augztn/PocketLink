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


enum DiscoverHomeItemType { track, playlist, album, artist, collection }

class DiscoverHomeItem {
  const DiscoverHomeItem({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.thumbnailUrl = '',
    this.videoId = '',
    this.browseId = '',
    this.params,
    this.durationText = '',
  });

  final DiscoverHomeItemType type;
  final String id;
  final String title;
  final String subtitle;
  final String thumbnailUrl;
  final String videoId;
  final String browseId;
  final String? params;
  final String durationText;

  bool get isPlayableTrack => type == DiscoverHomeItemType.track && videoId.isNotEmpty;

  factory DiscoverHomeItem.fromJson(Map<String, dynamic> json) {
    final videoId = json['videoId']?.toString() ?? '';
    final rawType = json['type']?.toString().toLowerCase() ?? '';
    final type = DiscoverHomeItemType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => videoId.isNotEmpty
          ? DiscoverHomeItemType.track
          : DiscoverHomeItemType.collection,
    );
    return DiscoverHomeItem(
      type: type,
      id: json['id']?.toString() ?? videoId,
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? json['artist']?.toString() ?? '',
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
      videoId: videoId,
      browseId: json['browseId']?.toString() ?? '',
      params: json['params']?.toString(),
      durationText: json['durationText']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'thumbnailUrl': thumbnailUrl,
    'videoId': videoId,
    'browseId': browseId,
    if (params != null) 'params': params,
    'durationText': durationText,
  };

  DiscoverTrack toTrack() => DiscoverTrack(
    videoId: videoId,
    title: title,
    artist: subtitle.isEmpty ? 'Discover' : subtitle,
    durationText: durationText,
    thumbnailUrl: thumbnailUrl,
  );
}

class DiscoverHomeShelf {
  const DiscoverHomeShelf({
    required this.title,
    required this.tracks,
    this.items = const [],
  });

  final String title;
  final List<DiscoverTrack> tracks;
  final List<DiscoverHomeItem> items;

  factory DiscoverHomeShelf.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => DiscoverHomeItem.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((item) => item.title.isNotEmpty && item.id.isNotEmpty)
        .toList(growable: false);
    final rawTracks = (json['tracks'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => DiscoverTrack.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((track) => track.videoId.isNotEmpty && track.title.isNotEmpty)
        .toList(growable: false);
    final tracks = rawTracks.isNotEmpty
        ? rawTracks
        : rawItems.where((item) => item.isPlayableTrack)
            .map((item) => item.toTrack()).toList(growable: false);
    return DiscoverHomeShelf(
      title: json['title']?.toString() ?? '',
      tracks: tracks,
      items: rawItems,
    );
  }
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
            .where((shelf) => shelf.title.isNotEmpty &&
                (shelf.tracks.isNotEmpty || shelf.items.isNotEmpty))
            .toList(growable: false),
        continuation: json['continuation']?.toString() ?? '',
      );
}

/// Appends continuation content without duplicating a track or collection.
List<DiscoverHomeShelf> mergeDiscoverHomeShelves(
  List<DiscoverHomeShelf> current,
  List<DiscoverHomeShelf> incoming,
) {
  final merged = <DiscoverHomeShelf>[];
  final seenItemKeys = <String>{};
  final seenTrackIds = <String>{};

  List<DiscoverHomeItem> uniqueItems(List<DiscoverHomeItem> items) =>
      items.where((item) => seenItemKeys.add('${item.type.name}:${item.id}'))
          .toList(growable: false);

  List<DiscoverTrack> uniqueTracks(List<DiscoverTrack> tracks) =>
      tracks.where((track) => seenTrackIds.add(track.videoId))
          .toList(growable: false);

  for (final shelf in current) {
    merged.add(DiscoverHomeShelf(
      title: shelf.title,
      tracks: uniqueTracks(shelf.tracks),
      items: uniqueItems(shelf.items),
    ));
  }

  for (final shelf in incoming) {
    final index = merged.indexWhere(
      (item) => item.title.toLowerCase() == shelf.title.toLowerCase(),
    );
    final freshItems = uniqueItems(shelf.items);
    final freshTracks = uniqueTracks(shelf.tracks);
    if (freshItems.isEmpty && freshTracks.isEmpty) continue;
    if (index < 0) {
      merged.add(DiscoverHomeShelf(
        title: shelf.title,
        tracks: freshTracks,
        items: freshItems,
      ));
    } else {
      merged[index] = DiscoverHomeShelf(
        title: merged[index].title,
        tracks: [...merged[index].tracks, ...freshTracks],
        items: [...merged[index].items, ...freshItems],
      );
    }
  }
  return List.unmodifiable(merged);
}


/// Builds the Discover hero from real feed and listening-history tracks.
/// Collection cards are included only when they carry a playable track ID.
List<DiscoverTrack> buildDiscoverSpotlightTracks({
  required List<DiscoverHomeShelf> shelves,
  required List<DiscoverTrack> recentlyPlayed,
  int limit = 5,
}) {
  if (limit <= 0) return const [];

  final result = <DiscoverTrack>[];
  final seen = <String>{};

  void add(DiscoverTrack track) {
    if (track.videoId.isEmpty || track.title.trim().isEmpty) return;
    if (seen.add(track.videoId) && result.length < limit) {
      result.add(track);
    }
  }

  for (final shelf in shelves) {
    for (final track in shelf.tracks) {
      add(track);
    }
    for (final item in shelf.items) {
      if (item.isPlayableTrack) add(item.toTrack());
    }
    if (result.length >= limit) break;
  }
  if (result.length < limit) {
    for (final track in recentlyPlayed) {
      add(track);
      if (result.length >= limit) break;
    }
  }

  return List.unmodifiable(result);
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
