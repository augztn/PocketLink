import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/now_playing_overlay_controller.dart';

void main() {
  group('NowPlayingOverlayController', () {
    tearDown(NowPlayingOverlayController.unregister);

    test('open invokes the registered handler once', () async {
      var calls = 0;
      NowPlayingOverlayController.register(() async {
        calls++;
      });

      NowPlayingOverlayController.open();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
    });


    test('coalesces overlapping open requests while the route is opening', () async {
      final completer = Completer<void>();
      var calls = 0;
      NowPlayingOverlayController.register(() async {
        calls++;
        await completer.future;
      });

      NowPlayingOverlayController.open();
      NowPlayingOverlayController.open();
      NowPlayingOverlayController.open();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      completer.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('open is a no-op after unregister', () async {
      var calls = 0;
      NowPlayingOverlayController.register(() async {
        calls++;
      });
      NowPlayingOverlayController.unregister();

      NowPlayingOverlayController.open();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
    });

    test('handler can complete asynchronously', () async {
      final completer = Completer<void>();
      var completed = false;
      NowPlayingOverlayController.register(() async {
        await completer.future;
        completed = true;
      });

      NowPlayingOverlayController.open();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      completer.complete();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isTrue);
    });
  });
}
