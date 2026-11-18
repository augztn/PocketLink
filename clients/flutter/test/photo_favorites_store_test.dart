import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/library/photo_favorites_store.dart';

void main() {
  late Directory directory;
  late PhotoFavoritesStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photo-favorites-test-');
    store = PhotoFavoritesStore(file: File('${directory.path}/favorites.json'));
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('loads an empty set when no favourites file exists', () async {
    expect(await store.load(), isEmpty);
  });

  test('persists and restores favourite identifiers', () async {
    await store.save({'internal:DCIM/photo.jpg', 'usb1:Pictures/image.png'});

    expect(await store.load(), {
      'internal:DCIM/photo.jpg',
      'usb1:Pictures/image.png',
    });
  });

  test('serializes overlapping writes in order', () async {
    final first = store.save({'first'});
    final second = store.save({'second'});

    await Future.wait([first, second]);
    expect(await store.load(), {'second'});
  });

  test('rejects malformed favourite data', () async {
    await store.file.writeAsString('{"not":"a list"}');

    expect(store.load(), throwsFormatException);
  });
}
