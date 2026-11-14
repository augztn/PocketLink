import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'features/media/persistent_audio_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PersistentAudioPlayer.instance;
  runApp(const HomeServerApp());
}
