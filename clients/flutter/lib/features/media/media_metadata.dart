/// Presentation helpers for metadata supplied by remote media catalogues.
String cleanMediaArtist(String? value, {String fallback = ''}) {
  final artist = (value ?? '').trim();
  if (artist.isEmpty) return fallback;
  return artist
      .replaceAll(
        RegExp(r'\s*[•·]\s*[0-9][0-9.,]*\s*[KMB]?\s+views?\s*$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String formatDiscoverArtist(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return '';
  final match = RegExp(r'^(.*?)(\s*[•·]\s*[0-9][0-9.,]*\s*[KMB]?\s+views?)$', caseSensitive: false).firstMatch(raw);
  final artist = (match?.group(1) ?? raw).trim();
  final suffix = match?.group(2) ?? '';
  if (RegExp(r'[\u0590-\u08FF]').hasMatch(artist)) {
    return '\u2068$artist\u2069$suffix';
  }
  return '$artist$suffix';
}


/// Resolves an artist without exposing the generic source label as metadata.
/// Embedded tags win; otherwise parse "Title - Artist", then a meaningful
/// parent folder/album name.
String resolveMediaArtist({
  required String? artist,
  required String title,
  required String path,
  String fallback = '',
}) {
  final tagged = cleanMediaArtist(artist);
  if (tagged.isNotEmpty) return tagged;

  var stem = title.trim();
  final dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot);
  final separator = stem.lastIndexOf(' - ');
  if (separator > 0 && separator + 3 < stem.length) {
    final parsed = stem.substring(separator + 3).trim();
    if (parsed.isNotEmpty && parsed.length <= 100) return parsed;
  }

  final parts = path.split('/').where((part) => part.trim().isNotEmpty).toList();
  if (parts.length > 1) {
    final folder = parts[parts.length - 2].trim();
    const genericFolders = {
      'music', 'audio', 'downloads', 'download', 'internal storage',
      'external storage', 'pocketlink', 'songs',
    };
    if (folder.isNotEmpty && !genericFolders.contains(folder.toLowerCase())) {
      return folder;
    }
  }

  final cleanFallback = fallback.trim();
  if (cleanFallback.isEmpty ||
      const {'pocketlink', 'discover', 'unknown'}.contains(cleanFallback.toLowerCase())) {
    return 'Unknown artist';
  }
  return cleanFallback;
}
