import 'package:flutter_test/flutter_test.dart';

import '../lib/features/home/browser_state_store.dart';

void main() {
  group('BrowserStateStore', () {
    test('retains Files navigation and presentation state per server', () {
      final store = BrowserStateStore();
      const state = FileBrowserState(
        path: 'Movies/2026',
        category: 'Videos',
        sortBy: 'newest',
        gridView: true,
        scrollOffset: 420,
      );

      store.updateFile('https://server-a.test:8000', state);

      expect(
        store.fileState('https://server-a.test:8000').path,
        'Movies/2026',
      );
      expect(
        store.fileState('https://server-a.test:8000').scrollOffset,
        420,
      );
      expect(
        store.fileState('https://server-b.test:8000').path,
        isEmpty,
      );
      store.dispose();
    });

    test('retains Music and Videos tabs and storage selections independently', () {
      final store = BrowserStateStore.instance;

      store.updateMedia(
        'https://server-a.test:8000',
        'music',
        const MediaBrowserState(
          folderPath: 'Music/Albums',
          selectedVolume: 'internal',
          view: 'folders',
          sortBy: 'largest',
        ),
      );
      store.updateMedia(
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
        store.mediaState('https://server-a.test:8000', 'music').view,
        'folders',
      );
      expect(
        store.mediaState('https://server-a.test:8000', 'music').selectedVolume,
        'internal',
      );
      expect(
        store.mediaState('https://server-a.test:8000', 'video').folderPath,
        'Movies',
      );
      expect(
        store.mediaState('https://server-a.test:8000', 'video').selectedVolume,
        'usb-123',
      );
      store.dispose();
    });
  });
}
