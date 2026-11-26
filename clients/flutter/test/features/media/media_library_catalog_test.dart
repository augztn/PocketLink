import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api.dart';
import 'package:pocketlink_client/features/media/media_library_catalog.dart';

FileEntry file(
  String name, {
  String type = 'file',
  int size = 0,
  String modified = '2026-01-01T00:00:00Z',
}) =>
    FileEntry(name: name, type: type, size: size, modified: modified);

MediaFileItem media(
  String path, {
  String? volume,
  int size = 0,
  String? modified,
  String? title,
  String? artist,
  String? album,
  int? durationMs,
  bool artworkAvailable = false,
}) =>
    MediaFileItem(
      entry: file(
        path.split('/').last,
        size: size,
        modified: modified ?? '2026-01-01T00:00:00Z',
      ),
      path: path,
      volume: volume,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      artworkAvailable: artworkAvailable,
    );

void main() {
  group('MediaLibraryCatalog.isMedia', () {
    test('filters by media type and accepts generic or missing MIME types', () {
      expect(
        MediaLibraryCatalog.isMedia(
          file('track.FLAC'),
          type: MediaLibraryType.music,
        ),
        isTrue,
      );
      expect(
        MediaLibraryCatalog.isMedia(
          file('movie.mp4'),
          type: MediaLibraryType.music,
        ),
        isFalse,
      );
      expect(
        MediaLibraryCatalog.isMedia(
          file('movie.mp4'),
          type: MediaLibraryType.video,
          mime: 'application/octet-stream',
        ),
        isTrue,
      );
    });

    test('rejects a supported extension paired with an unrelated MIME type', () {
      expect(
        MediaLibraryCatalog.isMedia(
          file('track.mp3'),
          type: MediaLibraryType.music,
          mime: 'video/mp4; charset=binary',
        ),
        isFalse,
      );
    });
  });

  group('MediaLibraryCatalog path and volume selection', () {
    final items = [
      media('Music/Albums/One/a.mp3'),
      media('Music/Albums/readme.mp3'),
      media('Music/Albums/Two/b.mp3'),
      media('Music/Albums/One/c.mp3', volume: 'usb1'),
      media('Music/Albums/One/nested/d.mp3'),
    ];

    test('returns only immediate files and groups immediate child folders', () {
      const catalog = MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: 'internal',
        currentFolderPath: 'Music/Albums',
        sortBy: 'name',
      );

      expect(
        catalog.filesAtCurrentLevel(items).map((item) => item.path),
        ['Music/Albums/readme.mp3'],
      );
      expect(
        catalog.foldersAtCurrentLevel(items).map((folder) => folder.name),
        ['One', 'Two'],
      );
      expect(
        catalog.foldersAtCurrentLevel(items).first.items
            .map((item) => item.path),
        ['Music/Albums/One/a.mp3', 'Music/Albums/One/nested/d.mp3'],
      );
    });

    test('does not confuse similarly prefixed folder names', () {
      const catalog = MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: 'internal',
        currentFolderPath: 'Music/Album',
        sortBy: 'name',
      );

      expect(catalog.filesAtCurrentLevel(items), isEmpty);
      expect(catalog.foldersAtCurrentLevel(items), isEmpty);
    });

    test('filters USB and internal entries independently', () {
      const catalog = MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: 'usb1',
        currentFolderPath: 'Music/Albums',
        sortBy: 'name',
      );

      expect(
        catalog.foldersAtCurrentLevel(items).single.volume,
        'usb1',
      );
    });
  });


  group('MediaLibraryCatalog folder-derived music collections', () {
    final items = [
      media('Music/Artist A/Album One/first.mp3'),
      media('Music/Artist A/Album One/second.mp3'),
      media('Music/Artist A/Album Two/third.mp3'),
      media('Music/Artist B/Album Three/fourth.mp3', volume: 'usb1'),
      media('Music/root-track.mp3'),
    ];

    test('groups albums by parent folder and keeps storage volumes separate', () {
      final groups = const MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: null,
        currentFolderPath: '',
        sortBy: 'name',
      ).albumsFromFolders(items);

      expect(groups.map((group) => group.name),
          ['Album One', 'Album Three', 'Album Two', 'Unsorted']);
      expect(groups.first.items.length, 2);
      expect(groups[1].volume, 'usb1');
      expect(groups.last.path, 'Music');
    });

    test('groups artists at the artist directory and handles root tracks', () {
      final groups = const MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: null,
        currentFolderPath: '',
        sortBy: 'name',
      ).artistsFromFolders(items);

      expect(groups.map((group) => group.name),
          ['Artist A', 'Artist B', 'Unknown artist']);
      expect(groups.first.items.length, 3);
      expect(groups.first.path, 'Music/Artist A');
      expect(groups[1].volume, 'usb1');
    });
  });

  group('MediaLibraryCatalog embedded music metadata', () {
    final tagged = [
      media('Music/Folder A/track-one.mp3',
          title: 'Track One', artist: 'Artist A', album: 'Shared Album',
          durationMs: 182000, artworkAvailable: true),
      media('Music/Folder B/track-two.flac',
          title: 'Track Two', artist: 'Artist A', album: 'Shared Album'),
      media('Music/Folder C/track-three.m4a',
          title: 'Track Three', artist: 'Artist B', album: 'Other Album'),
      media('Music/USB/track-four.mp3',
          volume: 'usb1', artist: 'Artist A', album: 'Shared Album'),
    ];

    test('groups albums by embedded tag across folders and separates volumes', () {
      final groups = const MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: null,
        currentFolderPath: '',
        sortBy: 'name',
      ).albumsFromFolders(tagged);

      final internalShared = groups.singleWhere(
        (group) => group.name == 'Shared Album' && group.volume == null,
      );
      expect(internalShared.items.map((item) => item.path),
          ['Music/Folder A/track-one.mp3', 'Music/Folder B/track-two.flac']);
      expect(groups.where((group) => group.name == 'Shared Album').length, 2);
    });

    test('groups artists by embedded tag across different albums', () {
      final groups = const MediaLibraryCatalog(
        type: MediaLibraryType.music,
        selectedVolume: null,
        currentFolderPath: '',
        sortBy: 'name',
      ).artistsFromFolders(tagged);

      final artistA = groups.singleWhere(
        (group) => group.name == 'Artist A' && group.volume == null,
      );
      expect(artistA.items.length, 2);
    });
  });

  group('MediaLibraryCatalog sorting', () {
    final items = [
      media('zeta.mp3', size: 40, modified: '2026-01-01T00:00:00Z'),
      media('Alpha.mp3', size: 10, modified: '2026-03-01T00:00:00Z'),
      media('beta.mp3', size: 20, modified: '2026-02-01T00:00:00Z'),
    ];

    test('sorts by name, size, and modification date', () {
      expect(
        const MediaLibraryCatalog(
          type: MediaLibraryType.music,
          selectedVolume: null,
          currentFolderPath: '',
          sortBy: 'name',
        ).sortMedia(items).map((item) => item.entry.name),
        ['Alpha.mp3', 'beta.mp3', 'zeta.mp3'],
      );
      expect(
        const MediaLibraryCatalog(
          type: MediaLibraryType.music,
          selectedVolume: null,
          currentFolderPath: '',
          sortBy: 'largest',
        ).sortMedia(items).map((item) => item.entry.name),
        ['zeta.mp3', 'beta.mp3', 'Alpha.mp3'],
      );
      expect(
        const MediaLibraryCatalog(
          type: MediaLibraryType.music,
          selectedVolume: null,
          currentFolderPath: '',
          sortBy: 'newest',
        ).sortMedia(items).map((item) => item.entry.name),
        ['Alpha.mp3', 'beta.mp3', 'zeta.mp3'],
      );
    });
  });
}
