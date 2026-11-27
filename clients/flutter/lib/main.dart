import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:progressive_background_blur/progressive_background_blur.dart'
    as shader_blur;

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/diagnostic_observer.dart';
import 'features/media/persistent_audio_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 60 << 20
    ..maximumSize = 120;
  await AppLogger.initialize();
  try {
    await shader_blur.ProgressiveBlur.precache();
  } catch (error, stack) {
    unawaited(AppLogger.warning(
      'Progressive blur shader preload failed; runtime fallback will be used',
      component: 'progressive_blur',
      fields: {'error': error.toString(), 'stack_trace': stack.toString()},
    ));
  }
  DiagnosticLifecycleObserver.instance.start();
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
  runApp(const PocketLinkApp());
}
