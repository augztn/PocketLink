import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/features/files/file_browser_state_store.dart';

void main() {
  group('FileBrowserStateStore', () {
    test('does not notify when an identical state is submitted', () {
      final store = FileBrowserStateStore();
      var notifications = 0;
      store.addListener(() => notifications++);
      const state = FileBrowserState(
        path: 'Movies',
        category: 'Videos',
        sortBy: 'name',
        gridView: false,
        scrollOffset: 64,
      );

      store.update('https://server-a.test:8000', state);
      store.update('https://server-a.test:8000', state);

      expect(notifications, 1);
      expect(store.stateFor('https://server-a.test:8000'), state);
      store.dispose();
    });

    test('treats scroll offset as part of state equality', () {
      final store = FileBrowserStateStore();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.update('server', const FileBrowserState(scrollOffset: 10));
      store.update('server', const FileBrowserState(scrollOffset: 20));

      expect(notifications, 2);
      expect(store.stateFor('server').scrollOffset, 20);
      store.dispose();
    });

    test('retains Files navigation and presentation state per server', () {
      final store = FileBrowserStateStore();
      const state = FileBrowserState(
        path: 'Movies/2026',
        selectedVolume: '188FECD93CDD48EB',
        category: 'Videos',
        sortBy: 'newest',
        gridView: true,
        scrollOffset: 420,
      );

      store.update('https://server-a.test:8000', state);

      expect(
        store.stateFor('https://server-a.test:8000').path,
        'Movies/2026',
      );
      expect(store.stateFor('https://server-a.test:8000').scrollOffset, 420);
      expect(
        store.stateFor('https://server-a.test:8000').selectedVolume,
        '188FECD93CDD48EB',
      );
      store.update(
        'https://server-a.test:8000',
        store.stateFor('https://server-a.test:8000')
            .copyWith(clearSelectedVolume: true),
      );
      expect(store.stateFor('https://server-a.test:8000').selectedVolume, isNull);
      expect(store.stateFor('https://server-b.test:8000').path, isEmpty);
      store.dispose();
    });
  });
}
