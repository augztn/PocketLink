import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/features/media/now_playing_scrubber.dart';

void main() {
  final settings = AppSettings.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.resetNowPlayingOptions();
  });

  test('Apple Capsule is the default scrubber style', () {
    expect(settings.nowPlayingScrubberStyle, 'apple');
    expect(
      NowPlayingScrubberStyle.fromKey('unknown'),
      NowPlayingScrubberStyle.appleCapsule,
    );
  });

  test('selected scrubber style persists without resetting playback', () async {
    await settings.setNowPlayingScrubberStyle('wavy');

    final preferences = await SharedPreferences.getInstance();
    expect(settings.nowPlayingScrubberStyle, 'wavy');
    expect(
      preferences.getString('settings_now_playing_scrubber_style'),
      'wavy',
    );
  });

  test('unsupported scrubber styles are rejected', () async {
    await expectLater(
      settings.setNowPlayingScrubberStyle('unsupported'),
      throwsArgumentError,
    );
  });
  testWidgets('unknown duration shows safe placeholder timestamps',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingScrubber(
            style: NowPlayingScrubberStyle.appleCapsule,
            position: Duration.zero,
            duration: Duration.zero,
            bufferedPosition: Duration.zero,
            isPlaying: false,
            isBuffering: true,
            onSeek: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all scrubber styles render', (tester) async {
    for (final style in NowPlayingScrubberStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NowPlayingScrubberPreview(style: style),
          ),
        ),
      );
      final preview = find.byType(NowPlayingScrubberPreview);
      expect(preview, findsOneWidget);
      expect(
        find.descendant(of: preview, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
    }
  });

}
