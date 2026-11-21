import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_app_bar.dart';

class VideoPlayerSettingsScreen extends StatelessWidget {
  const VideoPlayerSettingsScreen({super.key});
  static const List<double> _timeouts = [2.0, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 0.0];
  static const _seeks = [5, 10, 15, 30];
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0];

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return AnimatedBuilder(animation: settings, builder: (context, _) => Scaffold(
      appBar: PocketLinkAppBar(title: const Text('Video player')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        _group('Playback & controls', [
          _choice<double>(icon: Icons.timer_outlined, title: 'Controls auto-hide', value: settings.videoControlsTimeoutSeconds, options: _timeouts, label: (v) => v == 0 ? 'Never' : '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString()} seconds', onChanged: (v) => settings.setVideoPlayerOptions(controlsTimeoutSeconds: v)),
          const Divider(height: 1),
          _choice<int>(icon: Icons.fast_forward_rounded, title: 'Double-tap seek', value: settings.videoSeekSeconds, options: _seeks, label: (v) => '$v seconds', onChanged: (v) => settings.setVideoPlayerOptions(seekSeconds: v)),
          const Divider(height: 1),
          _choice<double>(icon: Icons.speed_rounded, title: 'Default playback speed', value: settings.videoDefaultSpeed, options: _speeds, label: (v) => '${v}×', onChanged: (v) => settings.setVideoPlayerOptions(defaultSpeed: v)),
          const Divider(height: 1),
          SwitchListTile(secondary: const Icon(Icons.gesture_rounded), title: const Text('Player gestures'), subtitle: const Text('Double-tap and horizontal swipe seeking; swipe left for brightness and right for volume'), value: settings.videoGesturesEnabled, onChanged: (v) => settings.setVideoPlayerOptions(gesturesEnabled: v)),
          const Divider(height: 1),
          SwitchListTile(secondary: const Icon(Icons.zoom_in_rounded), title: const Text('Pinch to zoom'), subtitle: const Text('Pinch to enlarge the video and pan around the frame'), value: settings.videoPinchZoomEnabled, onChanged: (v) => settings.setVideoPlayerOptions(pinchZoomEnabled: v)),
          const Divider(height: 1),
          SwitchListTile(secondary: const Icon(Icons.touch_app_rounded), title: const Text('Tap to play or pause'), subtitle: const Text('Single tap on the video toggles playback'), value: settings.videoTapToTogglePlayback, onChanged: (v) => settings.setVideoPlayerOptions(tapToTogglePlayback: v)),
          const Divider(height: 1),
          SwitchListTile(secondary: const Icon(Icons.fullscreen_rounded), title: const Text('Open videos in fullscreen'), subtitle: const Text('Automatically enter fullscreen when a video starts'), value: settings.videoAutoFullscreen, onChanged: (v) => settings.setVideoPlayerOptions(autoFullscreen: v)),
          const Divider(height: 1),
          _choice<String>(icon: Icons.screen_rotation_rounded, title: 'Fullscreen orientation', value: settings.videoFullscreenOrientation, options: const ['landscape', 'portrait', 'auto'], label: (v) => switch (v) { 'portrait' => 'Portrait', 'auto' => 'Follow device', _ => 'Landscape' }, onChanged: (v) => settings.setVideoPlayerOptions(fullscreenOrientation: v)),
        ]),
        const SizedBox(height: 12),
        _group('Video appearance', [
          _choice<String>(icon: Icons.fit_screen_rounded, title: 'Video scaling', value: settings.videoFitMode, options: const ['contain', 'cover', 'fill'], label: (v) => switch (v) { 'cover' => 'Crop to fill', 'fill' => 'Stretch to fill', _ => 'Fit (show full frame)' }, onChanged: (v) => settings.setVideoPlayerOptions(fitMode: v)),
        ]),
        const SizedBox(height: 12),
        _group('Subtitles', [
          ListTile(leading: const Icon(Icons.text_fields_rounded), title: const Text('Subtitle text size'), subtitle: Slider(min: 14, max: 32, divisions: 9, value: settings.videoSubtitleFontSize, label: '${settings.videoSubtitleFontSize.round()} px', onChanged: (v) => settings.setVideoPlayerOptions(subtitleFontSize: v)), trailing: Text('${settings.videoSubtitleFontSize.round()}')),
          const Divider(height: 1),
          SwitchListTile(secondary: const Icon(Icons.subtitles_rounded), title: const Text('Subtitle background'), subtitle: const Text('Translucent background behind subtitles'), value: settings.videoSubtitleBackground, onChanged: (v) => settings.setVideoPlayerOptions(subtitleBackground: v)),
        ]),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: settings.resetVideoPlayerOptions, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset to defaults'))),
      ]),
    ));
  }

  Widget _group(String title, List<Widget> children) => Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
    ...children,
  ]));

  Widget _choice<T>({required IconData icon, required String title, required T value, required List<T> options, required String Function(T) label, required ValueChanged<T> onChanged}) => ListTile(
    leading: Icon(icon), title: Text(title), subtitle: Text(label(value)),
    trailing: PopupMenuButton<T>(initialValue: value, onSelected: onChanged, itemBuilder: (_) => options.map((v) => PopupMenuItem<T>(value: v, child: Text(label(v)))).toList()),
  );
}