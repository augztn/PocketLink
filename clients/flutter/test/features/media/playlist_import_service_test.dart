import 'package:flutter_test/flutter_test.dart';

import 'package:pocketlink_client/features/media/playlist_import_service.dart';
import 'package:pocketlink_client/features/media/discover/imported_playlist_manager_screen.dart';

void main() {
  group('PlaylistImportService', () {
    test('imports CSV rows into separate playlists and preserves quoted fields', () {
      const csv = 'Track name,Artist name,Album,Playlist name,ISRC\r\n'
          '"Song, Part 1","Artist ""A""",Album,Chill,USABC123\r\n'
          'Second Song,Artist B,Album,Workout,USABC456\r\n';
      final playlists = PlaylistImportService.parseCsvPlaylists(csv);

      expect(playlists, hasLength(2));
      expect(playlists[0].name, 'Chill');
      expect(playlists[0].tracks.single.title, 'Song, Part 1');
      expect(playlists[0].tracks.single.artist, 'Artist "A"');
      expect(playlists[1].name, 'Workout');
      expect(playlists[1].tracks.single.isrc, 'USABC456');
    });

    test('exports CSV that can be imported again without losing playlist grouping', () {
      final playlists = [
        const ImportedPlaylist(name: 'First', tracks: [
          ImportedTrack(title: 'One', artist: 'Artist 1'),
        ]),
        const ImportedPlaylist(name: 'Second', tracks: [
          ImportedTrack(title: 'Two', artist: 'Artist 2'),
        ]),
      ];
      final rows = [
        for (final playlist in playlists)
          for (final track in playlist.tracks)
            (playlist: playlist.name, track: track),
      ];

      final restored = PlaylistImportService.parseCsvPlaylists(
        PlaylistImportService.exportCsv(rows),
      );

      expect(restored.map((item) => item.name), ['First', 'Second']);
      expect(restored.map((item) => item.tracks.single.title), ['One', 'Two']);
    });

    test('matches Unicode titles and partial multi-artist metadata', () {
      expect(
        PlaylistImportService.isSameTrack(
          const ImportedTrack(title: 'നീലാകാശം', artist: 'Artist A, Artist B'),
          const ImportedTrack(title: 'നീലാകാശം', artist: 'Artist A'),
        ),
        isTrue,
      );
      expect(
        PlaylistImportService.isSameTrack(
          const ImportedTrack(title: 'Song (Official Audio)', artist: 'Artist'),
          const ImportedTrack(title: 'Song', artist: 'Artist'),
        ),
        isTrue,
      );
    });

    test('imports M3U entries with metadata and source paths', () {
      final playlist = PlaylistImportService.parseM3u(
        '#EXTM3U\n#EXTINF:210,Artist - Song\n/music/song.flac\n',
        fallbackPlaylistName: 'M3U import',
      );

      expect(playlist.name, 'M3U import');
      expect(playlist.tracks.single.title, 'Song');
      expect(playlist.tracks.single.artist, 'Artist');
      expect(playlist.tracks.single.sourcePath, '/music/song.flac');
    });
  });

  group('ImportedPlaylist server backup format', () {
    test('round-trips playlist metadata and track identifiers', () {
      const playlist = ImportedPlaylist(
        name: 'Saved playlist',
        provider: 'YouTube',
        sourceUrl: 'https://music.youtube.com/playlist?list=example',
        tracks: [
          ImportedTrack(
            title: 'Song',
            artist: 'Artist',
            videoId: 'abcdefghijk',
            sourcePath: '/music/song.flac',
          ),
        ],
      );

      final restored = ImportedPlaylist.fromJson(playlist.toJson());
      expect(restored.name, playlist.name);
      expect(restored.provider, playlist.provider);
      expect(restored.sourceUrl, playlist.sourceUrl);
      expect(restored.tracks.single.videoId, 'abcdefghijk');
      expect(restored.tracks.single.sourcePath, '/music/song.flac');
    });

    test('uses a dedicated folder on the PocketLink server', () {
      expect(ImportedPlaylistStore.folderPath, 'PocketLink/Discover/Playlists');
      expect(ImportedPlaylistStore.filePath, 'PocketLink/Discover/Playlists/playlists.json');
    });
  });
}
