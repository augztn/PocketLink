import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent disk + Flutter image-cache backed artwork shared by media surfaces.
abstract final class DiscoverThumbnailCache {
  static final Map<String, Uint8List> _memory = {};
  static final Map<String, Future<Uint8List?>> _pending = {};
  static const int _maxBytes = 8 * 1024 * 1024;

  /// Resizes Google-hosted YouTube Music artwork when its URL carries a
  /// size suffix; other providers keep their original URL unchanged.
  static String urlForSize(String url, int size) => url.replaceFirst(
        RegExp(r'=w\\d+-h\\d+(?:-[^?&]*)?(?=$|[?&])'),
        '=w$size-h$size',
      );

  static Future<Uint8List?> load(String url) {
    if (url.isEmpty) return Future.value(null);
    final cached = _memory[url];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(url, () async {
      try {
        final directory = await getApplicationSupportDirectory();
        final cacheDirectory = Directory('${directory.path}/artwork_cache');
        if (!await cacheDirectory.exists()) {
          await cacheDirectory.create(recursive: true);
        }
        final file = File('${cacheDirectory.path}/${sha256.convert(url.codeUnits)}.img');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty && bytes.length <= _maxBytes) {
            _memory[url] = bytes;
            return bytes;
          }
          await file.delete();
        }

        final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
        try {
          final request = await client.getUrl(Uri.parse(url)).timeout(
            const Duration(seconds: 15),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
          if (response.statusCode < 200 || response.statusCode >= 300) return null;
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response.timeout(const Duration(seconds: 15))) {
            if (builder.length + chunk.length > _maxBytes) return null;
            builder.add(chunk);
          }
          final bytes = builder.takeBytes();
          if (bytes.isEmpty) return null;
          await file.writeAsBytes(bytes, flush: true);
          _memory[url] = bytes;
          return bytes;
        } finally {
          client.close(force: true);
        }
      } catch (_) {
        return null;
      } finally {
        _pending.remove(url);
      }
    });
  }
}

class DiscoverThumbnail extends StatelessWidget {
  const DiscoverThumbnail({
    required this.url,
    required this.cacheWidth,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.errorFallback,
    super.key,
  });

  final String url;
  final int cacheWidth;
  final Widget fallback;
  final BoxFit fit;
  final Widget? errorFallback;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return fallback;
    return FutureBuilder<Uint8List?>(
      future: DiscoverThumbnailCache.load(url),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) return fallback;
        if (bytes == null || bytes.isEmpty) return errorFallback ?? fallback;
        return Image.memory(
          bytes,
          cacheWidth: cacheWidth,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        );
      },
    );
  }
}
