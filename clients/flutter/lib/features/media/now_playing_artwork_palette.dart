import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Generates the ambient player colors from track metadata or album artwork.
abstract final class NowPlayingArtworkPalette {
  static List<Color> fallback({
    required String title,
    required String folderName,
    required String path,
  }) {
    var hash = 2166136261;
    for (final unit in utf8.encode('$title|$folderName|$path')) {
      hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    final first = HSLColor.fromAHSL(1, hue, 0.72, 0.54).toColor();
    final second = HSLColor.fromAHSL(1, (hue + 76) % 360, 0.68, 0.48).toColor();
    final dark = HSLColor.fromAHSL(1, hue, 0.42, 0.10).toColor();
    return [first, second, dark];
  }

  static Future<List<Color>?> extract(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 48,
        targetHeight: 48,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;

      final candidates = <({Color color, double saturation, double hue})>[];
      for (var y = 1; y < image.height; y += 3) {
        for (var x = 1; x < image.width; x += 3) {
          final offset = (y * image.width + x) * 4;
          final alpha = data.getUint8(offset + 3);
          if (alpha < 180) continue;
          final color = Color.fromARGB(
            alpha,
            data.getUint8(offset),
            data.getUint8(offset + 1),
            data.getUint8(offset + 2),
          );
          final hsl = HSLColor.fromColor(color);
          if (hsl.lightness < 0.12 || hsl.lightness > 0.88) continue;
          candidates.add((
            color: color,
            saturation: hsl.saturation,
            hue: hsl.hue,
          ));
        }
      }
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => b.saturation.compareTo(a.saturation));
      final primary = candidates.first;
      if (primary.saturation < 0.22) return null;
      final secondary = candidates.firstWhere(
        (item) {
          final distance = (item.hue - primary.hue).abs();
          return item.saturation > 0.25 &&
              math.min(distance, 360 - distance) > 32;
        },
        orElse: () => (
          color: HSLColor.fromAHSL(
            1,
            (primary.hue + 76) % 360,
            0.68,
            0.48,
          ).toColor(),
          saturation: 0.68,
          hue: (primary.hue + 76) % 360,
        ),
      );
      final darkColor = HSLColor.fromColor(primary.color)
          .withLightness(0.10)
          .withSaturation(0.48)
          .toColor();
      return [primary.color, secondary.color, darkColor];
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
