import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/now_playing_artwork_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fallback palette is deterministic for a track', () {
    final first = NowPlayingArtworkPalette.fallback(
      title: 'Track',
      folderName: 'Album',
      path: 'Music/Album/Track.flac',
    );
    final second = NowPlayingArtworkPalette.fallback(
      title: 'Track',
      folderName: 'Album',
      path: 'Music/Album/Track.flac',
    );
    final other = NowPlayingArtworkPalette.fallback(
      title: 'Different track',
      folderName: 'Album',
      path: 'Music/Album/Other.flac',
    );

    expect(first, hasLength(3));
    expect(second, first);
    expect(other, isNot(first));
  });

  test('extracts a three-color palette from artwork', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 48, 48),
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(48, 48);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    final palette = await NowPlayingArtworkPalette.extract(
      data!.buffer.asUint8List(),
    );

    expect(palette, hasLength(3));
    expect(palette!.first, const Color(0xFFFF0000));
  });

  test('invalid artwork returns no palette', () async {
    expect(
      await NowPlayingArtworkPalette.extract(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
  });
}
