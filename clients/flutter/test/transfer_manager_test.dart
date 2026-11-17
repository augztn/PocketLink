import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/features/transfers/transfer_history_store.dart';
import 'package:homeserver_client/features/transfers/transfer_manager.dart';

void main() {
  late Directory directory;
  late TransferHistoryStore store;
  late TransferManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('homeserver-transfers-');
    store = TransferHistoryStore(file: File('${directory.path}/history.json'));
    manager = TransferManager.forTesting(store);
  });

  tearDown(() async {
    manager.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('records progress and completed transfers', () async {
    final completed = await manager.run(
      name: 'photo.jpg',
      direction: 'Upload',
      location: 'Internal storage',
      operation: (token, progress) async {
        progress(50, 100);
        progress(100, 100);
      },
    );

    expect(completed, isTrue);
    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.status, TransferStatus.completed);
    expect(manager.tasks.single.transferred, 100);
    expect(manager.tasks.single.progress, 1);
    expect(await store.load(), hasLength(1));
  });

  test('records failures and retries with the original operation', () async {
    var attempts = 0;
    final operation = (token, progress) async {
      attempts++;
      if (attempts == 1) throw StateError('temporary network error');
      progress(100, 100);
    };
    final completed = await manager.run(
      name: 'retry.zip',
      direction: 'Download',
      location: 'USB drive',
      operation: operation,
    );

    expect(completed, isFalse);
    final failedId = manager.tasks.single.id;
    expect(manager.tasks.single.status, TransferStatus.failed);
    expect(await manager.retry(failedId), isTrue);
    expect(attempts, 2);
    expect(manager.tasks.first.status, TransferStatus.completed);
    expect(manager.tasks, hasLength(2));
  });

  test('cancellation marks the transfer cancelled', () async {
    final completed = await manager.run(
      name: 'large.bin',
      direction: 'Download',
      location: 'Internal storage',
      operation: (token, progress) async {
        progress(10, 100);
        token.cancel('test cancellation');
      },
    );

    expect(completed, isFalse);
    expect(manager.tasks.single.status, TransferStatus.cancelled);
  });

  test('clears finished tasks but preserves active tasks', () async {
    final completer = Completer<void>();
    final running = manager.run(
      name: 'active.bin',
      direction: 'Upload',
      location: 'USB drive',
      operation: (token, progress) => completer.future,
    );
    await Future<void>.delayed(Duration.zero);
    await manager.run(
      name: 'done.bin',
      direction: 'Upload',
      location: 'USB drive',
      operation: (token, progress) async {},
    );

    await manager.clearFinished();
    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.name, 'active.bin');

    manager.cancel(manager.tasks.single.id);
    completer.complete();
    await running;
  });

  test('restores history after manager recreation', () async {
    await manager.run(
      name: 'persisted.jpg',
      direction: 'Upload',
      location: 'Internal storage',
      operation: (token, progress) async => progress(40, 40),
    );

    final restored = TransferManager.forTesting(store);
    await restored.ready;
    expect(restored.tasks, hasLength(1));
    expect(restored.tasks.single.name, 'persisted.jpg');
    expect(restored.tasks.single.status, TransferStatus.completed);
    restored.dispose();
  });

  test('restores only the newest 100 history entries', () async {
    final now = DateTime.now();
    await store.save(List.generate(105, (index) => {
      'id': 'history-$index',
      'name': 'file-$index',
      'direction': 'Download',
      'location': 'Internal storage',
      'startedAt': now.subtract(Duration(minutes: index)).toIso8601String(),
      'transferred': 1,
      'total': 1,
      'status': 'completed',
    }).reversed.toList());

    final restored = TransferManager.forTesting(store);
    await restored.ready;
    expect(restored.tasks, hasLength(100));
    expect(restored.tasks.first.name, 'file-0');
    expect(restored.tasks.last.name, 'file-99');
    restored.dispose();
  });

  test('keeps completed transfer history bounded in memory', () async {
    for (var index = 0; index < 105; index++) {
      await manager.run(
        name: 'file-$index.bin',
        direction: 'Download',
        location: 'Internal storage',
        operation: (token, progress) async {},
      );
    }

    expect(manager.tasks, hasLength(100));
    expect(await store.load(), hasLength(100));
  });

  test('marks interrupted transfers as failed on restore', () async {
    await store.save([{
      'id': 'interrupted-1',
      'name': 'unfinished.bin',
      'direction': 'Download',
      'location': 'USB drive',
      'startedAt': DateTime.now().toIso8601String(),
      'transferred': 20,
      'total': 100,
      'status': 'running',
    }]);

    final restored = TransferManager.forTesting(store);
    await restored.ready;
    expect(restored.tasks.single.status, TransferStatus.failed);
    expect(restored.tasks.single.error, contains('App closed'));
    restored.dispose();
  });
}
