import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/features/media/media_browser_state_store.dart';

void main() {
  group('MediaBrowserStateStore', () {
    test('retains Music and Videos tabs and storage selections independently', () {
      final store = MediaBrowserStateStore();

      store.update(
        'https://server-a.test:8000',
        'music',
        const MediaBrowserState(
          folderPath: 'Music/Albums',
          selectedVolume: 'internal',
          view: 'folders',
          sortBy: 'largest',
          layoutMode: 'list',
          scrollOffset: 286,
        ),
      );
      store.update(
        'https://server-a.test:8000',
        'video',
        const MediaBrowserState(
          folderPath: 'Movies',
          selectedVolume: 'usb-123',
          view: 'all',
          sortBy: 'newest',
        ),
      );

      expect(
        store.stateFor('https://server-a.test:8000', 'music').view,
        'folders',
      );
      expect(
        store.stateFor('https://server-a.test:8000', 'music').selectedVolume,
        'internal',
      );
      expect(store.stateFor('https://server-a.test:8000', 'music').scrollOffset, 286);
      expect(store.stateFor('https://server-a.test:8000', 'music').layoutMode, 'list');
      store.update(
        'https://server-a.test:8000',
        'music',
        store.stateFor('https://server-a.test:8000', 'music')
            .copyWith(clearSelectedVolume: true),
      );
      expect(
        store.stateFor('https://server-a.test:8000', 'music').selectedVolume,
        isNull,
      );
      expect(
        store.stateFor('https://server-a.test:8000', 'video').folderPath,
        'Movies',
      );
      expect(
        store.stateFor('https://server-a.test:8000', 'video').selectedVolume,
        'usb-123',
      );
      store.dispose();
    });
  });
}
