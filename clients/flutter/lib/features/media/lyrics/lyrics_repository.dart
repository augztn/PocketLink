import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/network/server_api.dart';
import '../persistent_audio_player.dart';

enum LyricsLookupStatus { loading, found, notFound, error }
class LyricsWord {
  const LyricsWord(this.startMs, this.endMs, this.text);
  final int startMs, endMs;
  final String text;
}
class LyricsLine {
  const LyricsLine(this.timeMs, this.text, {this.words = const []});
  final int timeMs;
  final String text;
  final List<LyricsWord> words;
}
class LyricsDocument {
  const LyricsDocument({required this.providerId, required this.providerName, required this.lines, required this.synced, this.wordSynced = false});
  final String providerId, providerName;
  final List<LyricsLine> lines;
  final bool synced, wordSynced;
}
class LyricsProviderResult {
  const LyricsProviderResult(this.status, {this.document, this.error});
  final LyricsLookupStatus status;
  final LyricsDocument? document;
  final String? error;
}
class LyricsTrackQuery {
  const LyricsTrackQuery({required this.track, required this.api});
  final MediaQueueItem track;
  final ServerApi? api;
  String get key => [track.lyricsVideoId ?? '', track.localPath ?? '', track.volume ?? '', track.path, track.title, track.artist ?? '', track.durationText, api?.baseUrl ?? ''].join('|');
  String get title => LyricsProvider.clean(track.title);
  String get artist => LyricsProvider.clean(track.artist ?? '');
  int get durationSeconds {
    final p = track.durationText.split(':').map(int.tryParse).toList();
    if (p.any((v) => v == null)) return 0;
    if (p.length == 2) return p[0]! * 60 + p[1]!;
    if (p.length == 3) return p[0]! * 3600 + p[1]! * 60 + p[2]!;
    return 0;
  }
}
abstract interface class LyricsProvider {
  String get id;
  String get name;
  Future<LyricsDocument?> fetch(LyricsTrackQuery query);
  static String clean(String s) => s
    .replaceAll(RegExp(r'^\s*(?:\d{1,3}\s*[-._)]\s*|\d{2}\s+)'), '')
    .replaceAll(RegExp(r'\.(flac|alac|wav|aiff|aif|mp3|m4a|opus|ogg|wv|ape|dsf|dff)$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s*\([^)]*(official|audio|video|lyrics?|remaster|visualizer|live|acoustic|karaoke)[^)]*\)', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s*\[[^]]*(official|audio|video|lyrics?|remaster|visualizer|live|acoustic|karaoke)[^]]*\]', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ').trim();
}
class LyricsRepository {
  LyricsRepository({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 7), receiveTimeout: const Duration(seconds: 10), headers: const {'User-Agent': 'PocketLink/1.0'})) {
    _providers = [_LocalProvider(), _LrclibProvider(_dio), _PlatformProvider('youtube_music', 'YouTube Music', 'discoverLyrics'), _PlatformProvider('youtube_captions', 'YouTube Captions', 'discoverCaptions'), _KugouProvider(_dio), _LyricsPlusProvider(_dio), _BetterLyricsProvider(_dio), _LrcRedProvider(_dio), _NoopProvider('musixmatch', 'Musixmatch'), _GeniusProvider(_dio)];
  }
  final Dio _dio;
  late final List<LyricsProvider> _providers;
  final Map<String, Map<String, LyricsProviderResult>> _states = {};
  final Map<String, Future<Map<String, LyricsProviderResult>>> _pending = {};
  final Map<String, LyricsDocument?> _active = {};
  static List<LyricsLine> parseLrc(String raw) {
    final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final lines = <LyricsLine>[];
    for (final row in raw.split(RegExp(r'\r?\n'))) {
      final matches = stamp.allMatches(row).toList();
      final text = row.replaceAll(stamp, '').trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        lines.add(LyricsLine(
          (int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!)) * 1000 +
              (int.tryParse(fraction) ?? 0),
          text,
        ));
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  static LyricsDocument? parseRawLyricsText(
    String rawText, {
    required String providerId,
    required String providerName,
  }) {
    final raw = rawText.trim();
    if (raw.isEmpty) return null;
    final syncedLines = parseLrc(raw);
    if (syncedLines.isNotEmpty) {
      return LyricsDocument(
        providerId: providerId,
        providerName: providerName,
        lines: syncedLines,
        synced: true,
      );
    }
    final plainLines = raw.split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty &&
            !RegExp(r'^\[(ti|ar|al|by|length|re|ve):', caseSensitive: false).hasMatch(line))
        .map((line) => LyricsLine(0, line))
        .toList();
    if (plainLines.isEmpty) return null;
    return LyricsDocument(
      providerId: providerId,
      providerName: providerName,
      lines: plainLines,
      synced: false,
    );
  }


  static LyricsDocument? selectBestLrclibCandidate(
    List<Map> candidates, {
    required String title,
    required String artist,
    int? durationSeconds,
  }) {
    String norm(String value) => LyricsProvider.clean(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final wantedTitle = norm(title);
    final wantedArtist = norm(artist);
    final titleTokens = wantedTitle.split(' ').where((s) => s.length > 1).toSet();
    final artistTokens = wantedArtist.split(' ').where((s) => s.length > 1).toSet();
    LyricsDocument? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in candidates) {
      final trackName = norm(candidate['trackName']?.toString() ?? candidate['name']?.toString() ?? '');
      final artistName = norm(candidate['artistName']?.toString() ?? '');
      final syncedRaw = candidate['syncedLyrics']?.toString() ?? '';
      final plainRaw = candidate['plainLyrics']?.toString() ?? '';
      final syncedLines = parseLrc(syncedRaw);
      final plainLines = plainRaw.split(RegExp(r'\r?\n'))
          .map((s) => s.trim()).where((s) => s.isNotEmpty)
          .map((s) => LyricsLine(0, s)).toList();
      final lines = syncedLines.isNotEmpty ? syncedLines : plainLines;
      if (lines.isEmpty) continue;
      final candidateTitleTokens = trackName.split(' ').where((s) => s.length > 1).toSet();
      final titleUnion = titleTokens.union(candidateTitleTokens).length;
      final titleSimilarity = trackName == wantedTitle
          ? 1.0
          : trackName.contains(wantedTitle) || wantedTitle.contains(trackName)
              ? .85
              : titleUnion == 0 ? 0.0 : titleTokens.intersection(candidateTitleTokens).length / titleUnion;
      final candidateArtistTokens = artistName.split(' ').where((s) => s.length > 1).toSet();
      final artistUnion = artistTokens.union(candidateArtistTokens).length;
      final artistSimilarity = artistName.isEmpty || wantedArtist.isEmpty
          ? .5
          : artistName == wantedArtist
              ? 1.0
              : artistName.contains(wantedArtist) || wantedArtist.contains(artistName)
                  ? .85
                  : artistUnion == 0 ? 0.0 : artistTokens.intersection(candidateArtistTokens).length / artistUnion;

      // Do not accept a same-duration cover or an unrelated artist just because
      // the candidate contains some overlapping title words.
      if (titleSimilarity < .4) continue;
      if (wantedArtist.isNotEmpty && artistName.isNotEmpty && artistSimilarity < .25) continue;

      var score = syncedLines.isNotEmpty ? 30.0 : 0.0;
      score += titleSimilarity * 45;
      if (wantedArtist.isNotEmpty && artistName.isNotEmpty) {
        score += artistSimilarity * 32;
      }
      final candidateDuration = (candidate['duration'] as num?)?.toInt();
      if (durationSeconds != null && candidateDuration != null) {
        final diff = (durationSeconds - candidateDuration).abs();
        score += diff <= 3 ? 25 : diff <= 8 ? 14 : diff <= 16 ? 5 : diff > 35 ? -25 : -6;
      }
      if (score > bestScore) {
        bestScore = score;
        best = LyricsDocument(
          providerId: 'lrclib',
          providerName: 'LRCLIB',
          lines: lines,
          synced: syncedLines.isNotEmpty,
        );
      }
    }
    return bestScore >= 15 ? best : null;
  }


  List<LyricsProvider> get providers => List.unmodifiable(_providers);
  LyricsDocument? current(String key) => _active[key];
  Map<String, LyricsProviderResult> resultsFor(String key) => Map.unmodifiable(_states[key] ?? const {});
  LyricsDocument? select(String key, String id) {
    final r = _states[key]?[id];
    if (r?.status != LyricsLookupStatus.found) return null;
    _active[key] = r!.document;
    return r.document;
  }
  Future<Map<String, LyricsProviderResult>> lookup(LyricsTrackQuery q, {void Function(Map<String, LyricsProviderResult>)? onUpdate}) {
    final old = _states[q.key];
    if (old != null && old.values.every((v) => v.status != LyricsLookupStatus.loading)) {
      onUpdate?.call(Map.unmodifiable(old)); return Future.value(Map.unmodifiable(old));
    }
    return _pending.putIfAbsent(q.key, () => _run(q, onUpdate));
  }
  Future<Map<String, LyricsProviderResult>> _run(LyricsTrackQuery q, void Function(Map<String, LyricsProviderResult>)? notify) async {
    final states = {for (final p in _providers) p.id: const LyricsProviderResult(LyricsLookupStatus.loading)};
    _states[q.key] = states;
    void publish() => notify?.call(Map.unmodifiable(Map.of(states)));
    publish();
    final jobs = {for (final p in _providers) p.id: p.fetch(q).timeout(const Duration(seconds: 12))};
    LyricsDocument? wordSynced, synced, plain;
    for (final p in _providers) {
      try {
        final doc = await jobs[p.id];
        states[p.id] = LyricsProviderResult(doc == null ? LyricsLookupStatus.notFound : LyricsLookupStatus.found, document: doc);
        if (doc != null && doc.lines.isNotEmpty) {
          if (doc.wordSynced) wordSynced ??= doc;
          else if (doc.synced) synced ??= doc;
          else plain ??= doc;
        }
      } catch (e) {
        states[p.id] = LyricsProviderResult(LyricsLookupStatus.error, error: e is TimeoutException ? 'Request timed out' : 'Provider unavailable');
      }
      publish();
    }
    _active[q.key] = wordSynced ?? synced ?? plain;
    _states[q.key] = Map.of(states);
    _pending.remove(q.key);
    return Map.unmodifiable(states);
  }
}
abstract class _Provider implements LyricsProvider {
  _Provider(this.dio);
  final Dio dio;
  Future<dynamic> _getJson(String url, [Map<String, dynamic>? params]) async => (await dio.get<dynamic>(url, queryParameters: params)).data;
  Future<String?> text(String url, [Map<String, dynamic>? params]) async => (await dio.get<String>(url, queryParameters: params, options: Options(responseType: ResponseType.plain))).data;
  LyricsDocument? lrc(String? raw, String id, String name) {
    if (raw == null) return null;
    final out = LyricsRepository.parseLrc(raw);
    return out.isEmpty ? null : LyricsDocument(providerId:id, providerName:name, lines:out, synced:true);
  }
  LyricsDocument? plain(String? raw, String id, String name) {
    if (raw == null || raw.trim().isEmpty) return null;
    final lines = raw.split(RegExp(r'\r?\n')).map((s)=>s.trim()).where((s)=>s.isNotEmpty).map((s)=>LyricsLine(0,s)).toList();
    return lines.isEmpty ? null : LyricsDocument(providerId:id, providerName:name, lines:lines, synced:false);
  }
}
class _LocalProvider extends _Provider {
  _LocalProvider():super(Dio());
  @override String get id=>'local';
  @override String get name=>'Local LRC (sidecar)';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final path=q.track.localPath ?? q.track.path, dot=path.lastIndexOf('.');
    final side=(dot>path.lastIndexOf('/')?path.substring(0,dot):path)+'.lrc';
    String? raw;
    if(q.track.localPath!=null) { final f=File(side); if(await f.exists()) raw=await f.readAsString(); }
    else if(q.api!=null) { try { final b=q.track.volume==null?await q.api!.downloadFile(side):await q.api!.downloadStorageFile(q.track.volume!,side); raw=utf8.decode(b,allowMalformed:true); } catch(_){} }
    // Embedded tag lyrics are not exposed by the current media metadata API.
    return LyricsRepository.parseRawLyricsText(raw ?? '', providerId: id, providerName: name);
  }
}
class _LrclibProvider extends _Provider {
  _LrclibProvider(super.dio);
  @override String get id=>'lrclib';
  @override String get name=>'LRCLIB';

  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    if (q.title.isEmpty) return null;
    final candidates = <Map>[];
    if (q.artist.isNotEmpty && q.durationSeconds > 0) {
      try {
        final exact = await _getJson('https://lrclib.net/api/get', {
          'track_name': q.title,
          'artist_name': _primaryArtist(q.artist),
          'duration': q.durationSeconds,
        });
        if (exact is Map) candidates.add(exact);
      } on DioException {
        // Exact lookup miss: continue with search.
      }
    }
    try {
      final structured = await _getJson('https://lrclib.net/api/search', {
        'track_name': q.title,
        if (q.artist.isNotEmpty) 'artist_name': _primaryArtist(q.artist),
      });
      if (structured is List) candidates.addAll(structured.whereType<Map>());
    } on DioException {
      // Continue to broad search below.
    }
    if (candidates.isEmpty) {
      final broad = await _getJson('https://lrclib.net/api/search', {
        'q': [q.title, _primaryArtist(q.artist)].where((s) => s.isNotEmpty).join(' '),
      });
      if (broad is List) candidates.addAll(broad.whereType<Map>());
    }
    return LyricsRepository.selectBestLrclibCandidate(
      candidates,
      title: q.title,
      artist: _primaryArtist(q.artist),
      durationSeconds: q.durationSeconds > 0 ? q.durationSeconds : null,
    );
  }

  static String _primaryArtist(String artist) => artist
      .split(RegExp(r'\s*(?:,|&|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bx\b|×|;|/)\s*', caseSensitive: false))
      .firstWhere((part) => part.trim().isNotEmpty, orElse: () => '')
      .trim();
}
class _PlatformProvider implements LyricsProvider {
  _PlatformProvider(this.id, this.name, this.method);
  static const MethodChannel _channel = MethodChannel('pocketlink/saf');
  @override final String id;
  @override final String name;
  final String method;
  @override
  Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final videoId = q.track.lyricsVideoId;
    if (videoId == null || videoId.isEmpty) return null;
    final payload = await _channel.invokeMapMethod<String, dynamic>(method, {
      'videoId': videoId,
      'region': AppSettings.instance.discoverRegion,
    });
    final rawLines = payload?['lines'];
    if (rawLines is! List) return null;
    final lines = rawLines.whereType<Map>().map((row) {
      final time = (row['timeMs'] as num?)?.toInt();
      final text = row['text']?.toString().trim() ?? '';
      return time == null || text.isEmpty ? null : LyricsLine(time, text);
    }).whereType<LyricsLine>().toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines.isEmpty ? null : LyricsDocument(
      providerId: id,
      providerName: name,
      lines: lines,
      synced: payload?['synced'] as bool? ?? lines.any((line) => line.timeMs > 0),
    );
  }
}

class _NoopProvider implements LyricsProvider {
  _NoopProvider(this.id,this.name);
  @override final String id; @override final String name;
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async => throw UnsupportedError('This provider is not connected to the current Android Discover bridge.');
}
class _KugouProvider extends _Provider {
  _KugouProvider(super.dio);
  @override String get id=>'kugou'; @override String get name=>'KuGou';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    if(q.title.isEmpty||q.artist.isEmpty)return null;
    final songs=await _getJson('https://mobileservice.kugou.com/api/v3/search/song',{'version':9108,'plat':0,'pagesize':8,'showtype':0,'keyword':q.title+' - '+q.artist});
    dynamic info;
    if (songs is Map) {
      final data = songs['data'];
      if (data is Map) info = data['info'];
    }
    if(info is! List)return null;
    final rows=info.whereType<Map>().toList()..sort((a,b)=>(((a['duration'] as num?)?.toInt()??0)-q.durationSeconds).abs().compareTo((((b['duration'] as num?)?.toInt()??0)-q.durationSeconds).abs()));
    for(final row in rows){
      final hit=await _getJson('https://lyrics.kugou.com/search',{'ver':1,'man':'yes','client':'pc','hash':row['hash']});
      final cs=hit is Map?hit['candidates']:null; if(cs is! List||cs.isEmpty)continue;
      final c=cs.first as Map;
      final dl=await _getJson('https://lyrics.kugou.com/download',{'fmt':'lrc','charset':'utf8','client':'pc','ver':1,'id':c['id'],'accesskey':c['accesskey']});
      final encoded=dl is Map?dl['content']?.toString():null; if(encoded==null)continue;
      final doc=lrc(utf8.decode(base64.decode(base64.normalize(encoded)),allowMalformed:true),id,name);
      if(doc!=null)return doc;
    }
    return null;
  }
}
class _LyricsPlusProvider extends _Provider {
  _LyricsPlusProvider(super.dio);
  @override String get id=>'lyrics_plus'; @override String get name=>'LyricsPlus';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    for(final host in ['https://lyricsplus.prjktla.my.id','https://lyricsplus.binimum.org']){
      try{
        final d=await _getJson('$host/v2/lyrics/get',{'title':q.title,'artist':q.artist,'duration':q.durationSeconds});
        final entries=d is Map?d['lyrics']:null;if(entries is! List)continue;
        final lines=entries.whereType<Map>().map((e){
          final t=(e['time'] as num?)?.toInt();
          final syllabus=e['syllabus'];
          final words=syllabus is List ? syllabus.whereType<Map>().map((w) {
            final start=(w['time'] as num?)?.toInt();
            final duration=(w['duration'] as num?)?.toInt() ?? 0;
            final text=w['text']?.toString() ?? '';
            return start==null || text.isEmpty ? null : LyricsWord(start,start+duration,text);
          }).whereType<LyricsWord>().toList() : <LyricsWord>[];
          final s=e['text']?.toString().trim().isNotEmpty == true
              ? e['text'].toString().trim()
              : words.map((word)=>word.text).join();
          return t==null||s.isEmpty?null:LyricsLine(t,s,words:words);
        }).whereType<LyricsLine>().toList()..sort((a,b)=>a.timeMs.compareTo(b.timeMs));
        if(lines.isNotEmpty)return LyricsDocument(
          providerId:id,providerName:name,lines:lines,synced:true,
          wordSynced:lines.any((line)=>line.words.isNotEmpty),
        );
      }catch(_){}
    }return null;
  }
}
class _BetterLyricsProvider extends _Provider {
  _BetterLyricsProvider(super.dio);
  @override String get id=>'better_lyrics'; @override String get name=>'BetterLyrics';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final d=await _getJson('https://lyrics-api.boidu.dev/getLyrics',{'s':q.title,'a':q.artist,'d':q.durationSeconds});
    if(d is String)return lrc(d,id,name)??plain(d,id,name);
    if(d is Map)return lrc((d['syncedLyrics']??d['lyrics']??d['lrc'])?.toString(),id,name)??plain((d['plainLyrics']??d['text'])?.toString(),id,name);
    return null;
  }
}
class _LrcRedProvider extends _Provider {
  _LrcRedProvider(super.dio);
  @override String get id=>'lrc_red'; @override String get name=>'lrc.red';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final d=await _getJson('https://lrc.red/search.json',{'q':q.title+' '+q.artist});
    final hits=d is Map?d['hits']:null;if(hits is! List)return null;
    for(final h in hits.whereType<Map>()){
      final code=h['isrc']?.toString().toUpperCase()??'';
      if(!RegExp(r'^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$').hasMatch(code))continue;
      final xml=await text('https://lrc.red/s/$code.ttml');
      final lines=<LyricsLine>[];
      for(final m in RegExp(r'<p[^>]*begin="([^"]+)"[^>]*>(.*?)</p>',dotAll:true).allMatches(xml??'')){
        final stamp=RegExp(r'^(?:(\d+):)?(\d{2}):(\d{2})(?:\.(\d+))?$').firstMatch(m.group(1)??'');if(stamp==null)continue;
        final ms=((int.tryParse(stamp.group(1)??'0')??0)*3600+(int.parse(stamp.group(2)!))*60+int.parse(stamp.group(3)!))*1000+(int.tryParse((stamp.group(4)??'').padRight(3,'0').substring(0,3))??0);
        final value=(m.group(2)??'').replaceAll(RegExp(r'<[^>]+>'),' ').replaceAll(RegExp(r'\s+'),' ').trim();
        if(value.isNotEmpty)lines.add(LyricsLine(ms,value));
      }
      if(lines.isNotEmpty)return LyricsDocument(providerId:id,providerName:name,lines:lines,synced:true);
    }return null;
  }
}
class _GeniusProvider extends _Provider {
  _GeniusProvider(super.dio);
  @override String get id=>'genius'; @override String get name=>'Genius';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final page=await text('https://genius.com/api/search/multi',{'q':q.artist+' '+q.title});if(page==null)return null;
    final url=RegExp(r'"url":"(https://genius\.com/[^"]+)"').firstMatch(page)?.group(1)?.replaceAll(r'\/','/');if(url==null)return null;
    final html=await text(url);if(html==null)return null;
    final blocks=RegExp(r'<div[^>]*data-lyrics-container="true"[^>]*>(.*?)</div>',dotAll:true).allMatches(html).map((m)=>m.group(1)??'').toList();
    final lyrics=blocks.join('\n').replaceAll(RegExp(r'<br\s*/?>',caseSensitive:false),'\n').replaceAll(RegExp(r'<[^>]+>'),' ').replaceAll('&amp;','&').replaceAll(RegExp(r'[ \t]+'),' ').trim();
    return plain(lyrics,id,name);
  }
}
