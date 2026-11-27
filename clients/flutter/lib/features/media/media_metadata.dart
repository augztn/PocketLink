/// Presentation helpers for metadata supplied by remote media catalogues.
String cleanMediaArtist(String? value, {String fallback = ''}) {
  final artist = (value ?? '').trim();
  if (artist.isEmpty) return fallback;
  return artist
      .replaceAll(
        RegExp(r'\\s*[•·]\\s*[0-9][0-9.,]*\\s*[KMB]?\\s+views?\\s*$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();
}

/// Keeps RTL artist names isolated from following LTR counts or separators.
String isolateRtlMetadata(String artist, String suffix) =>
    '\u2068$artist\u2069$suffix';
