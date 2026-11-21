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
}) =>
    MediaFileItem(
      entry: file(
        path.split('/').last,
        size: size,
        modified: modified ?? '2026-01-01T00:00:00Z',
      ),
      path: path,
      volume: volume,
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
        isEmpty,
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

  group('MediaLibraryCatalog sorting', () {
    final items = [
      media('zeta.mp3', size: 10, modified: '2026-01-01T00:00:00Z'),
      media('Alpha.mp3', size: 30, modified: '2026-03-01T00:00:00Z'),
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
        ['Alpha.mp3', 'beta.mp3', 'zeta.mp3'],
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
