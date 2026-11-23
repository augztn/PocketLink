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
