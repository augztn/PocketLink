import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/features/files/file_browser_state_store.dart';

void main() {
  group('FileBrowserStateStore', () {
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
