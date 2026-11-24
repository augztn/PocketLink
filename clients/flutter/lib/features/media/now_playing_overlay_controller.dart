import 'dart:async';

import 'package:flutter/animation.dart';

/// App-level entry point for opening the active music player without pushing a route.
abstract final class NowPlayingOverlayController {
  static Future<void> Function()? _openHandler;
  static Future<void> Function()? _collapseHandler;
  static Animation<double>? expandProgress;

  static void register(
    Future<void> Function() handler, {
    Animation<double>? progress,
    Future<void> Function()? collapseHandler,
  }) {
    _openHandler = handler;
    _collapseHandler = collapseHandler;
    expandProgress = progress;
  }

  static void unregister() {
    _openHandler = null;
    _collapseHandler = null;
    expandProgress = null;
  }

  static void open() {
    final handler = _openHandler;
    if (handler != null) unawaited(handler());
  }

  static Future<void> collapse() async {
    final handler = _collapseHandler;
    if (handler != null) await handler();
  }
}
