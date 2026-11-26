import '../../core/network/server_api.dart';

enum MediaLibraryType { music, video }

class MediaFileItem {
  const MediaFileItem({required this.entry, required this.path, this.volume});

  final FileEntry entry;
  final String path;
  final String? volume;
}

class MediaFolderGroup {
  const MediaFolderGroup({
    required this.name,
    required this.path,
    required this.volume,
    required this.items,
  });

  final String name;
  final String path;
  final String? volume;
  final List<MediaFileItem> items;
}

/// Pure media-library filtering, grouping, and sorting rules.
///
/// Keeping these rules outside the screen makes path/volume behavior
/// independently testable and prevents UI state from owning catalog logic.

/// A folder-derived music collection. The current index exposes file paths but
/// not ID3 album/artist tags, so these groups intentionally use directory names.
class MediaCollectionGroup {
  const MediaCollectionGroup({
    required this.name,
    required this.path,
    required this.volume,
    required this.items,
  });

  final String name;
  final String path;
  final String? volume;
  final List<MediaFileItem> items;
}

class MediaLibraryCatalog {
  const MediaLibraryCatalog({
    required this.type,
    required this.selectedVolume,
    required this.currentFolderPath,
    required this.sortBy,
  });

  final MediaLibraryType type;
  final String? selectedVolume;
  final String currentFolderPath;
  final String sortBy;

  static const _audioExtensions = {
    'mp3', 'flac', 'm4a', 'wav', 'ogg', 'aac', 'opus', 'wma',
    'alac', 'aiff', 'aif', 'wv', 'ape', 'dsf', 'dff',
  };
  static const _videoExtensions = {
    'mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v', '3gp', 'ts',
  };
  static const _audioMimeTypes = {
    'audio/mpeg', 'audio/flac', 'audio/x-flac', 'audio/mp4', 'audio/x-m4a',
    'audio/wav', 'audio/x-wav', 'audio/ogg', 'audio/aac', 'audio/opus',
    'audio/x-ms-wma', 'audio/aiff', 'audio/x-aiff', 'audio/alac', 'audio/x-alac',
  };
  static const _videoMimeTypes = {
    'video/mp4', 'video/x-m4v', 'video/x-matroska', 'video/webm',
    'video/quicktime', 'video/x-msvideo', 'video/3gpp', 'video/mp2t',
  };

  static bool isMedia(
    FileEntry item, {
    required MediaLibraryType type,
    String? mime,
  }) {
    final extension = item.name.contains('.')
        ? item.name.split('.').last.toLowerCase()
        : '';
    final allowedExtension =
        (type == MediaLibraryType.music ? _audioExtensions : _videoExtensions)
            .contains(extension);
    if (!allowedExtension) return false;

    final normalizedMime = mime?.split(';').first.trim().toLowerCase() ?? '';
    if (normalizedMime.isEmpty ||
        normalizedMime == 'application/octet-stream') {
      return true;
    }
    return (type == MediaLibraryType.music ? _audioMimeTypes : _videoMimeTypes)
        .contains(normalizedMime);
  }

  List<MediaFolderGroup> foldersAtCurrentLevel(List<MediaFileItem> items) {
    final grouped = <String, List<MediaFileItem>>{};
    final prefix = _pathParts(currentFolderPath);
    for (final media in items) {
      final source = media.volume ?? 'internal';
      if (selectedVolume != null && source != selectedVolume) continue;
      final parts = _pathParts(media.path);
      if (parts.length <= prefix.length + 1) continue;
      if (!_startsWithParts(parts, prefix)) continue;

      final folderPath = parts.take(prefix.length + 1).join('/');
      final key = '$source::$folderPath';
      grouped.putIfAbsent(key, () => <MediaFileItem>[]).add(media);
    }

    final result = grouped.entries.map((entry) {
      final separator = entry.key.indexOf('::');
      final source = entry.key.substring(0, separator);
      final path = entry.key.substring(separator + 2);
      return MediaFolderGroup(
        name: path.split('/').last,
        path: path,
        volume: source == 'internal' ? null : source,
        items: entry.value,
      );
    }).toList();

    result.sort((a, b) {
      if (sortBy == 'largest') {
        final aSize = a.items.fold<int>(0, (sum, item) => sum + item.entry.size);
        final bSize = b.items.fold<int>(0, (sum, item) => sum + item.entry.size);
        return bSize.compareTo(aSize);
      }
      if (sortBy == 'newest') {
        DateTime newest(MediaFolderGroup folder) => folder.items
            .map((item) => DateTime.tryParse(item.entry.modified))
            .whereType<DateTime>()
            .fold<DateTime>(
              DateTime.fromMillisecondsSinceEpoch(0),
              (latest, date) => date.isAfter(latest) ? date : latest,
            );
        return newest(b).compareTo(newest(a));
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  List<MediaFileItem> filesAtCurrentLevel(List<MediaFileItem> items) {
    final prefix = _pathParts(currentFolderPath);
    return items.where((media) {
      final source = media.volume ?? 'internal';
      if (selectedVolume != null && source != selectedVolume) return false;
      final parts = _pathParts(media.path);
      return parts.length == prefix.length + 1 &&
          _startsWithParts(parts, prefix);
    }).toList();
  }

  List<MediaFileItem> sortMedia(List<MediaFileItem> items) {
    final result = List<MediaFileItem>.of(items);
    if (sortBy == 'largest') {
      result.sort((a, b) => b.entry.size.compareTo(a.entry.size));
    } else if (sortBy == 'newest') {
      result.sort((a, b) {
        final aDate = DateTime.tryParse(a.entry.modified);
        final bDate = DateTime.tryParse(b.entry.modified);
        return (bDate?.millisecondsSinceEpoch ?? 0)
            .compareTo(aDate?.millisecondsSinceEpoch ?? 0);
      });
    } else {
      result.sort((a, b) =>
          a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    }
    return result;
  }


  /// Groups tracks by their immediate parent directory as an album fallback.
  /// This does not claim to read embedded album tags.
  List<MediaCollectionGroup> albumsFromFolders(List<MediaFileItem> items) {
    final groups = <String, List<MediaFileItem>>{};
    final paths = <String, ({String name, String path, String? volume})>{};
    for (final item in items) {
      final separator = item.path.lastIndexOf('/');
      final parent = separator < 0 ? '' : item.path.substring(0, separator);
      final parts = _pathParts(parent);
      final isMusicRoot = parts.length == 1 && parts.first.toLowerCase() == 'music';
      final name = parent.isEmpty || isMusicRoot ? 'Unsorted' : parts.last;
      final key = '${item.volume ?? 'internal'}::${parent}';
      groups.putIfAbsent(key, () => <MediaFileItem>[]).add(item);
      paths[key] = (name: name, path: parent, volume: item.volume);
    }
    return _collectionGroups(groups, paths);
  }

  /// Uses the artist-level directory for Music/Artist/Album/Track layouts.
  /// Other layouts fall back to the nearest sensible parent directory.
  List<MediaCollectionGroup> artistsFromFolders(List<MediaFileItem> items) {
    final groups = <String, List<MediaFileItem>>{};
    final paths = <String, ({String name, String path, String? volume})>{};
    for (final item in items) {
      final separator = item.path.lastIndexOf('/');
      final parent = separator < 0 ? '' : item.path.substring(0, separator);
      final parts = _pathParts(parent);
      final first = parts.isEmpty ? '' : parts.first.toLowerCase();
      final hasMusicRoot = const {'music', 'audio', 'songs', 'artists'}.contains(first);
      final artistParts = hasMusicRoot
          ? (parts.length > 1 ? parts.take(2).toList(growable: false) : const <String>[])
          : (parts.length > 1 ? parts.take(parts.length - 1).toList(growable: false) : parts);
      final artistPath = artistParts.join('/');
      final name = artistParts.isEmpty ? 'Unknown artist' : artistParts.last;
      final key = '${item.volume ?? 'internal'}::${artistPath}';
      groups.putIfAbsent(key, () => <MediaFileItem>[]).add(item);
      paths[key] = (name: name, path: artistPath, volume: item.volume);
    }
    return _collectionGroups(groups, paths);
  }

  List<MediaCollectionGroup> _collectionGroups(
    Map<String, List<MediaFileItem>> groups,
    Map<String, ({String name, String path, String? volume})> paths,
  ) {
    final result = <MediaCollectionGroup>[];
    for (final entry in groups.entries) {
      final info = paths[entry.key]!;
      final tracks = List<MediaFileItem>.of(entry.value)
        ..sort((a, b) => a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
      result.add(MediaCollectionGroup(
        name: info.name,
        path: info.path,
        volume: info.volume,
        items: List.unmodifiable(tracks),
      ));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(result);
  }

  static List<String> _pathParts(String path) =>
      path.split('/').where((part) => part.isNotEmpty).toList();

  static bool _startsWithParts(List<String> path, List<String> prefix) {
    for (var index = 0; index < prefix.length; index++) {
      if (path[index] != prefix[index]) return false;
    }
    return true;
  }
}
