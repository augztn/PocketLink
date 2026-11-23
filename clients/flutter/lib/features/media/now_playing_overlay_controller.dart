import 'dart:async';

import 'package:flutter/animation.dart';

/// App-level entry point for opening the active music player without pushing a route.
abstract final class NowPlayingOverlayController {
  static Future<void> Function()? _openHandler;
  static Animation<double>? expandProgress;

  static void register(
    Future<void> Function() handler, {
    Animation<double>? progress,
  }) {
    _openHandler = handler;
    expandProgress = progress;
  }

  static void unregister() {
    _openHandler = null;
    expandProgress = null;
  }

  static void open() {
    final handler = _openHandler;
    if (handler != null) unawaited(handler());
  }
}
