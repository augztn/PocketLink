import 'dart:convert';
import 'package:dio/dio.dart';

class ImportedTrack {
  const ImportedTrack({required this.title, this.artist = '', this.album = '', this.isrc, this.sourcePath, this.videoId});
  final String title, artist, album;
  final String? isrc, sourcePath, videoId;
  Map<String, dynamic> toJson() => {'title': title, 'artist': artist, 'album': album, if (isrc != null) 'isrc': isrc, if (sourcePath != null) 'sourcePath': sourcePath, if (videoId != null) 'videoId': videoId};
  factory ImportedTrack.fromJson(Map<String, dynamic> json) => ImportedTrack(title: json['title']?.toString() ?? '', artist: json['artist']?.toString() ?? '', album: json['album']?.toString() ?? '', isrc: json['isrc']?.toString(), sourcePath: json['sourcePath']?.toString(), videoId: json['videoId']?.toString());
}
class ImportedPlaylist {
  const ImportedPlaylist({required this.name, required this.tracks});
  final String name;
  final List<ImportedTrack> tracks;
}
enum PlaylistMatchSource { localLossless, online, unmatched }
class PlaylistTrackMatch {
  const PlaylistTrackMatch({required this.track, required this.source, this.localPath, this.volume, this.videoId});
  final ImportedTrack track;
  final PlaylistMatchSource source;
  final String? localPath, volume, videoId;
}
class PlaylistImportProgress {
  const PlaylistImportProgress({required this.processed, required this.total, required this.localLossless, required this.online, required this.unmatched});
  final int processed, total, localLossless, online, unmatched;
}
class PlaylistUrlResult {
  const PlaylistUrlResult({required this.name, required this.tracks, this.provider});
  final String name;
  final List<ImportedTrack> tracks;
  final String? provider;
}

class PlaylistImportService {
  PlaylistImportService({Dio? client}) : _client = client ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15), headers: const {'User-Agent': 'Mozilla/5.0 PocketLink/1.0'}));
  final Dio _client;
  static const _titleHeaders = ['track name', 'title', 'song', 'name', 'track'];
  static const _artistHeaders = ['artist name', 'artist name(s)', 'artist', 'artists'];
  static const _albumHeaders = ['album', 'album name'];
  static const _playlistHeaders = ['playlist name', 'playlist'];
  static const _isrcHeaders = ['isrc', 'track isrc'];

  static ImportedPlaylist parseCsv(String input, {String fallbackPlaylistName = 'Imported playlist'}) {
    final rows = _parseCsvRows(input.replaceFirst('\uFEFF', '')).where((r) => r.any((v) => v.trim().isNotEmpty)).toList();
    if (rows.length < 2) throw const FormatException('The CSV does not contain any track rows.');
    final header = rows.first.map(_normalizeHeader).toList();
    int col(List<String> names) { for (final n in names) { final i = header.indexOf(_normalizeHeader(n)); if (i >= 0) return i; } return -1; }
    final ti = col(_titleHeaders), ai = col(_artistHeaders), al = col(_albumHeaders), pi = col(_playlistHeaders), ii = col(_isrcHeaders);
    if (ti < 0) throw const FormatException('Could not find a track title column in this CSV.');
    String cell(List<String> row, int i) => i < 0 || i >= row.length ? '' : row[i].trim();
    final names = <String>{}, tracks = <ImportedTrack>[];
    for (final row in rows.skip(1)) {
      final title = cell(row, ti); if (title.isEmpty) continue;
      final playlist = cell(row, pi); if (playlist.isNotEmpty) names.add(playlist);
      tracks.add(ImportedTrack(title: title, artist: cell(row, ai), album: cell(row, al), isrc: cell(row, ii).isEmpty ? null : cell(row, ii)));
    }
    if (tracks.isEmpty) throw const FormatException('No valid tracks were found in the CSV.');
    return ImportedPlaylist(name: names.length == 1 ? names.single : fallbackPlaylistName, tracks: List.unmodifiable(tracks));
  }

  static ImportedPlaylist parseM3u(String input, {String fallbackPlaylistName = 'Imported playlist'}) {
    final tracks = <ImportedTrack>[];
    String? title, artist;
    for (final raw in const LineSplitter().convert(input.replaceFirst('\uFEFF', ''))) {
      final line = raw.trim(); if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        final comma = line.indexOf(','); if (comma < 0) continue;
        final meta = line.substring(comma + 1).trim(), sep = meta.indexOf(' - ');
        artist = sep > 0 ? meta.substring(0, sep).trim() : '';
        title = sep > 0 ? meta.substring(sep + 3).trim() : meta;
      } else if (!line.startsWith('#')) {
        final filename = line.split(RegExp(r'[/\\]')).last;
        tracks.add(ImportedTrack(title: title?.isNotEmpty == true ? title! : filename.replaceFirst(RegExp(r'\.[^.]+$'), ''), artist: artist ?? '', sourcePath: line));
        title = null; artist = null;
      }
    }
    if (tracks.isEmpty) throw const FormatException('No playable entries were found in this M3U file.');
    return ImportedPlaylist(name: fallbackPlaylistName, tracks: List.unmodifiable(tracks));
  }

  Future<PlaylistUrlResult> importPublicUrl(String value, {CancelToken? cancelToken}) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) throw const FormatException('Enter a valid public playlist URL.');
    final host = uri.host.toLowerCase();
    final spotify = host == 'spotify.com' || host.endsWith('.spotify.com');
    final youtube = host == 'youtube.com' || host.endsWith('.youtube.com') || host == 'youtu.be';
    if (!spotify && !youtube) throw const FormatException('Supported links are public YouTube Music, YouTube and Spotify playlists.');
    final html = (await _client.get<String>(uri.toString(), cancelToken: cancelToken, options: Options(responseType: ResponseType.plain))).data ?? '';
    if (spotify) {
      final title = _meta(html, 'og:title') ?? 'Spotify playlist';
      final tracks = _spotifyTracks(html);
      if (tracks.isEmpty) throw const FormatException('Spotify did not expose this playlist. It may be private or rate-limited; export it as CSV with TuneMyMusic, Soundiiz or Exportify and import that file.');
      return PlaylistUrlResult(name: title, tracks: List.unmodifiable(tracks), provider: 'Spotify');
    }
    final title = _meta(html, 'og:title') ?? 'YouTube playlist';
    final ids = <String>{};
    for (final m in RegExp(r'"videoId"\s*:\s*"([A-Za-z0-9_-]{11})"').allMatches(html)) { ids.add(m.group(1)!); }
    if (ids.isEmpty) throw const FormatException('Could not read tracks from this YouTube playlist. Try a public playlist URL or import a CSV export.');
    return PlaylistUrlResult(name: title, tracks: List.unmodifiable(ids.map((id) => ImportedTrack(title: 'YouTube track', videoId: id))), provider: 'YouTube');
  }

  static String normalizeTrackText(String value) {
    var s = value.toLowerCase();
    s = s.replaceAll(RegExp(r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring)\b[^\)\]]*[\)\]]', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\s*[\(\[][^)\]]*(remaster(ed)?|mono|stereo)[^)\]]*[\)\]]', caseSensitive: false), ' ');
    s = s.replaceAll('&amp;', '&').replaceAll('&', ' and ').replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return s.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
  static bool isSameTrack(ImportedTrack a, ImportedTrack b) {
    final at = normalizeTrackText(a.title), bt = normalizeTrackText(b.title), aa = normalizeTrackText(a.artist), ba = normalizeTrackText(b.artist);
    return at.isNotEmpty && at == bt && (aa.isEmpty || ba.isEmpty || aa == ba);
  }

  static Future<List<PlaylistTrackMatch>> matchTracks({required List<ImportedTrack> tracks, required Future<PlaylistTrackMatch?> Function(ImportedTrack) findLocal, required Future<PlaylistTrackMatch?> Function(ImportedTrack) findOnline, required bool Function() isCancelled, required void Function(PlaylistImportProgress) onProgress, int maxConcurrency = 3}) async {
    var next = 0, local = 0, online = 0, unmatched = 0, done = 0;
    final results = List<PlaylistTrackMatch?>.filled(tracks.length, null);
    Future<void> worker() async {
      while (!isCancelled()) {
        final index = next++; if (index >= tracks.length) return;
        final track = tracks[index];
        var match = await findLocal(track);
        if (match == null && !isCancelled()) match = await findOnline(track);
        if (isCancelled()) return;
        if (match == null || match.source == PlaylistMatchSource.unmatched) { unmatched++; match = PlaylistTrackMatch(track: track, source: PlaylistMatchSource.unmatched); }
        else if (match.source == PlaylistMatchSource.localLossless) { local++; } else { online++; }
        results[index] = match; done++;
        onProgress(PlaylistImportProgress(processed: done, total: tracks.length, localLossless: local, online: online, unmatched: unmatched));
      }
    }
    await Future.wait(List.generate(maxConcurrency.clamp(1, 4).toInt(), (_) => worker()));
    return List.unmodifiable(results.whereType<PlaylistTrackMatch>());
  }

  static String exportCsv(Iterable<({String playlist, ImportedTrack track})> rows) {
    final out = StringBuffer('Track name,Artist name,Album,Playlist name,ISRC\r\n');
    for (final r in rows) { out.writeln([r.track.title, r.track.artist, r.track.album, r.playlist, r.track.isrc ?? ''].map(_csv).join(',')); }
    return out.toString();
  }
  static String exportM3u8(Iterable<({String playlist, ImportedTrack track, String location})> rows) {
    final out = StringBuffer('#EXTM3U\n');
    for (final r in rows) { out.writeln('#EXTINF:-1,' + (r.track.artist.isEmpty ? r.track.title : r.track.artist + ' - ' + r.track.title)); out.writeln(r.location); }
    return out.toString();
  }
  static String _csv(String s) => RegExp(r'[,"\r\n]').hasMatch(s) ? '"' + s.replaceAll('"', '""') + '"' : s;
  static String _normalizeHeader(String s) => s.replaceFirst('\uFEFF', '').trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ');

  static List<List<String>> _parseCsvRows(String input) {
    final first = input.split(RegExp(r'\r?\n')).first;
    final delimiter = first.split(';').length > first.split(',').length ? ';' : ',';
    final rows = <List<String>>[]; var row = <String>[]; final field = StringBuffer(); var quoted = false;
    void endField() { row.add(field.toString()); field.clear(); }
    void endRow() { endField(); rows.add(row); row = <String>[]; }
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quoted) {
        if (c == '"' && i + 1 < input.length && input[i + 1] == '"') { field.write('"'); i++; }
        else if (c == '"') { quoted = false; } else { field.write(c); }
      } else if (c == '"' && field.isEmpty) { quoted = true; }
      else if (c == delimiter) { endField(); }
      else if (c == '\n') { endRow(); }
      else if (c != '\r') { field.write(c); }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    if (quoted) throw const FormatException('The CSV contains an unclosed quoted field.');
    return rows;
  }
  static String? _meta(String html, String key) {
    final k = RegExp.escape(key);
    for (final p in [RegExp('<meta[^>]+property=["\\x27]$k["\\x27][^>]+content=["\\x27]([^"\\x27]*)["\\x27]', caseSensitive: false), RegExp('<meta[^>]+content=["\\x27]([^"\\x27]*)["\\x27][^>]+property=["\\x27]$k["\\x27]', caseSensitive: false)]) {
      final m = p.firstMatch(html); if (m != null) return m.group(1)!.replaceAll('&amp;', '&').replaceAll('&quot;', '"');
    }
    return null;
  }
  static List<ImportedTrack> _spotifyTracks(String html) {
    final found = <ImportedTrack>[], seen = <String>{};
    final p = RegExp(r'"track"\s*:\s*\{[^{}]{0,2000}?"name"\s*:\s*"((?:\\.|[^"\\])*)"');
    for (final m in p.allMatches(html)) {
      final title = _jsonString(m.group(1)!); if (title.isEmpty) continue;
      final window = html.substring(m.start, (m.start + 2400).clamp(0, html.length));
      final artistRaw = RegExp(r'"artists"\s*:\s*\[\s*\{[^{}]*"name"\s*:\s*"((?:\\.|[^"\\])*)"').firstMatch(window)?.group(1);
      final artist = artistRaw == null ? '' : _jsonString(artistRaw);
      final key = normalizeTrackText(title) + '|' + normalizeTrackText(artist);
      if (seen.add(key)) found.add(ImportedTrack(title: title, artist: artist));
    }
    return found;
  }
  static String _jsonString(String s) { try { return jsonDecode('"$s"') as String; } catch (_) { return s; } }
}
