import 'dart:async';

/// App-level entry point for opening the active music player without pushing a route.
abstract final class NowPlayingOverlayController {
  static Future<void> Function()? _openHandler;

  static void register(Future<void> Function() handler) {
    _openHandler = handler;
  }

  static void unregister() {
    _openHandler = null;
  }

  static void open() {
    final handler = _openHandler;
    if (handler != null) unawaited(handler());
  }
}
