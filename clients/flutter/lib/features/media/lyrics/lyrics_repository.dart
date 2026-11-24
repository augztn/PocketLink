import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/network/server_api.dart';
import '../persistent_audio_player.dart';

enum LyricsLookupStatus { loading, found, notFound, error }
class LyricsLine {
  const LyricsLine(this.timeMs, this.text);
  final int timeMs;
  final String text;
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
    return p.length == 2 && p.every((v) => v != null) ? p[0]! * 60 + p[1]! : 0;
  }
}
abstract interface class LyricsProvider {
  String get id;
  String get name;
  Future<LyricsDocument?> fetch(LyricsTrackQuery query);
  static String clean(String s) => s
    .replaceAll(RegExp(r'\s*\([^)]*(official|audio|video|lyrics?|remaster)[^)]*\)', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s*\[[^]]*(official|audio|video|lyrics?|remaster)[^]]*\]', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ').trim();
}
class LyricsRepository {
  LyricsRepository({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 7), receiveTimeout: const Duration(seconds: 10), headers: const {'User-Agent': 'PocketLink/1.0'})) {
    _providers = [_LocalProvider(), _LrclibProvider(_dio), _NoopProvider('youtube_music', 'YouTube Music'), _NoopProvider('youtube_captions', 'YouTube Captions'), _KugouProvider(_dio), _LyricsPlusProvider(_dio), _BetterLyricsProvider(_dio), _LrcRedProvider(_dio), _NoopProvider('musixmatch', 'Musixmatch'), _GeniusProvider(_dio)];
  }
  final Dio _dio;
  late final List<LyricsProvider> _providers;
  final Map<String, Map<String, LyricsProviderResult>> _states = {};
  final Map<String, Future<Map<String, LyricsProviderResult>>> _pending = {};
  final Map<String, LyricsDocument?> _active = {};
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
    LyricsDocument? synced, plain;
    for (final p in _providers) {
      try {
        final doc = await jobs[p.id];
        states[p.id] = LyricsProviderResult(doc == null ? LyricsLookupStatus.notFound : LyricsLookupStatus.found, document: doc);
        if (doc != null && doc.lines.isNotEmpty) {
          if (doc.synced) synced ??= doc; else plain ??= doc;
        }
      } catch (e) {
        states[p.id] = LyricsProviderResult(LyricsLookupStatus.error, error: e is TimeoutException ? 'Request timed out' : 'Provider unavailable');
      }
      publish();
    }
    _active[q.key] = synced ?? plain;
    _states[q.key] = Map.of(states);
    _pending.remove(q.key);
    return Map.unmodifiable(states);
  }
}
abstract class _Provider implements LyricsProvider {
  _Provider(this.dio);
  final Dio dio;
  Future<dynamic> json(String url, [Map<String, dynamic>? params]) async => (await dio.get<dynamic>(url, queryParameters: params)).data;
  Future<String?> text(String url, [Map<String, dynamic>? params]) async => (await dio.get<String>(url, queryParameters: params)).data;
  LyricsDocument? lrc(String? raw, String id, String name) {
    if (raw == null) return null;
    final re = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final out = <LyricsLine>[];
    for (final row in raw.split(RegExp(r'\r?\n'))) {
      final ms = re.allMatches(row).toList();
      final value = row.replaceAll(re, '').trim();
      if (value.isEmpty) continue;
      for (final m in ms) {
        final fraction = (m.group(3) ?? '').padRight(3, '0');
        out.add(LyricsLine((int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000 + (int.tryParse(fraction) ?? 0), value));
      }
    }
    out.sort((a,b) => a.timeMs.compareTo(b.timeMs));
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
  @override String get name=>'Embedded / Local LRC';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final path=q.track.localPath ?? q.track.path, dot=path.lastIndexOf('.');
    final side=(dot>path.lastIndexOf('/')?path.substring(0,dot):path)+'.lrc';
    String? raw;
    if(q.track.localPath!=null) { final f=File(side); if(await f.exists()) raw=await f.readAsString(); }
    else if(q.api!=null) { try { final b=q.track.volume==null?await q.api!.downloadFile(side):await q.api!.downloadStorageFile(q.track.volume!,side); raw=utf8.decode(b,allowMalformed:true); } catch(_){} }
    // Embedded tag lyrics are not exposed by the current media metadata API.
    return lrc(raw,id,name);
  }
}
class _LrclibProvider extends _Provider {
  _LrclibProvider(super.dio);
  @override String get id=>'lrclib'; @override String get name=>'LRCLIB';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    if(q.title.isEmpty)return null;
    final data=await json('https://lrclib.net/api/search',{'track_name':q.title,if(q.artist.isNotEmpty)'artist_name':q.artist});
    if(data is! List)return null;
    Map? best; var top=0.0;
    for(final r in data.whereType<Map>()){
      final t=LyricsProvider.clean(r['trackName']?.toString()??'').toLowerCase();
      final a=LyricsProvider.clean(r['artistName']?.toString()??'').toLowerCase();
      final s=_sim(q.title.toLowerCase(),t)*.7+(q.artist.isEmpty ? 0.5 : _sim(q.artist.toLowerCase(),a))*.3;
      if(s>top){top=s;best=r;}
    }
    if(best==null||top<.65)return null;
    return lrc(best['syncedLyrics']?.toString(),id,name)??plain(best['plainLyrics']?.toString(),id,name);
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
    final songs=await json('https://mobileservice.kugou.com/api/v3/search/song',{'version':9108,'plat':0,'pagesize':8,'showtype':0,'keyword':q.title+' - '+q.artist});
    final info=songs is Map?(songs['data'] as Map?)?['info']:null;
    if(info is! List)return null;
    final rows=info.whereType<Map>().toList()..sort((a,b)=>(((a['duration'] as num?)?.toInt()??0)-q.durationSeconds).abs().compareTo((((b['duration'] as num?)?.toInt()??0)-q.durationSeconds).abs()));
    for(final row in rows){
      final hit=await json('https://lyrics.kugou.com/search',{'ver':1,'man':'yes','client':'pc','hash':row['hash']});
      final cs=hit is Map?hit['candidates']:null; if(cs is! List||cs.isEmpty)continue;
      final c=cs.first as Map;
      final dl=await json('https://lyrics.kugou.com/download',{'fmt':'lrc','charset':'utf8','client':'pc','ver':1,'id':c['id'],'accesskey':c['accesskey']});
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
        final d=await json('$host/v2/lyrics/get',{'title':q.title,'artist':q.artist,'duration':q.durationSeconds});
        final entries=d is Map?d['lyrics']:null;if(entries is! List)continue;
        final lines=entries.whereType<Map>().map((e){final t=(e['time'] as num?)?.toInt();final s=e['text']?.toString().trim()??'';return t==null||s.isEmpty?null:LyricsLine(t,s);}).whereType<LyricsLine>().toList()..sort((a,b)=>a.timeMs.compareTo(b.timeMs));
        if(lines.isNotEmpty)return LyricsDocument(providerId:id,providerName:name,lines:lines,synced:true);
      }catch(_){}
    }return null;
  }
}
class _BetterLyricsProvider extends _Provider {
  _BetterLyricsProvider(super.dio);
  @override String get id=>'better_lyrics'; @override String get name=>'BetterLyrics';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final d=await json('https://lyrics-api.boidu.dev/getLyrics',{'s':q.title,'a':q.artist,'d':q.durationSeconds});
    if(d is String)return lrc(d,id,name)??plain(d,id,name);
    if(d is Map)return lrc((d['syncedLyrics']??d['lyrics']??d['lrc'])?.toString(),id,name)??plain((d['plainLyrics']??d['text'])?.toString(),id,name);
    return null;
  }
}
class _LrcRedProvider extends _Provider {
  _LrcRedProvider(super.dio);
  @override String get id=>'lrc_red'; @override String get name=>'lrc.red';
  @override Future<LyricsDocument?> fetch(LyricsTrackQuery q) async {
    final d=await json('https://lrc.red/search.json',{'q':q.title+' '+q.artist});
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
double _sim(String a,String b){if(a==b&&a.isNotEmpty)return 1;if(a.isEmpty||b.isEmpty)return 0;final x=a.split(' ').toSet(),y=b.split(' ').toSet();return x.intersection(y).length/x.union(y).length;}
