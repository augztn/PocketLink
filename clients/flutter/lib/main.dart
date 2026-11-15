import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'features/media/persistent_audio_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initialize();
  MediaKit.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(AppLogger.error('Flutter framework error', error: details.exception, stackTrace: details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(AppLogger.error('Uncaught platform error', error: error, stackTrace: stack));
    return false;
  };
  PersistentAudioPlayer.instance;
  runApp(const HomeServerApp());
}
