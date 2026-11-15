import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/features/transfers/transfer_manager.dart';

void main() {
  final manager = TransferManager.instance;

  setUp(() => manager.clearFinished());

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
  });

  test('records failures without throwing to the caller', () async {
    final completed = await manager.run(
      name: 'broken.zip',
      direction: 'Download',
      location: 'USB drive',
      operation: (token, progress) async {
        throw StateError('disk unavailable');
      },
    );

    expect(completed, isFalse);
    expect(manager.tasks.single.status, TransferStatus.failed);
    expect(manager.tasks.single.error, contains('disk unavailable'));
  });

  test('cancellation marks the transfer cancelled', () async {
    final completed = await manager.run(
      name: 'large.bin',
      direction: 'Download',
      location: 'Internal storage',
      operation: (token, progress) async {
        progress(10, 100);
        token.cancel('test cancellation');
        token.throwIfCancellationRequested();
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

    manager.clearFinished();
    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.name, 'active.bin');

    manager.cancel(manager.tasks.single.id);
    completer.complete();
    await running;
  });
}
