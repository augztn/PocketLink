import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/core/network/server_api.dart';

void main() {
  group('ServerApi', () {
    test('accepts host and port without a scheme', () {
      expect(
        () => ServerApi(
          baseUrl: '192.168.1.10:8000',
          username: 'admin',
          password: 'secret',
        ),
        returnsNormally,
      );
    });

    test('rejects invalid addresses', () {
      expect(
        () => ServerApi(
          baseUrl: 'not a valid address',
          username: 'admin',
          password: 'secret',
        ),
        throwsFormatException,
      );
    });

    test('rejects embedded credentials in URL', () {
      expect(
        () => ServerApi(
          baseUrl: 'http://user:password@example.com:8000',
          username: 'admin',
          password: 'secret',
        ),
        throwsFormatException,
      );
    });
    test('parses SAF listings with numeric modified timestamps', () {
      final listing = DirectoryListing.fromJson({
        'path': '',
        'items': [
          {
            'name': 'movie.mp4',
            'type': 'file',
            'size': 1024,
            'modified': 1794528000000,
          },
        ],
      });

      expect(listing.items.single.modified, '1794528000000');
      expect(listing.items.single.size, 1024);
    });

    test('parses separate external storage volume status', () {
      final volume = StorageVolume.fromJson({
        'id': 'usb1',
        'name': 'USB Storage 1',
        'available': true,
        'writable': true,
      });

      expect(volume.id, 'usb1');
      expect(volume.available, isTrue);
      expect(volume.writable, isTrue);
    });

    test('parses the existing backend file listing format', () {
      final listing = DirectoryListing.fromJson({
        'path': '.',
        'items': [
          {
            'name': 'Documents',
            'type': 'directory',
            'size': 0,
            'modified': '2026-11-13T00:00:00+00:00',
          },
          {
            'name': 'notes.txt',
            'type': 'file',
            'size': 42,
            'modified': '2026-11-13T00:00:00+00:00',
          },
        ],
      });

      expect(listing.path, '.');
      expect(listing.items, hasLength(2));
      expect(listing.items.first.isDirectory, isTrue);
      expect(listing.items.last.name, 'notes.txt');
      expect(listing.items.last.size, 42);
    });
  });
}
