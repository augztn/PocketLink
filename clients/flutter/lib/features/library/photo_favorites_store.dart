import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PhotoFavoritesStore {
  PhotoFavoritesStore({required this.file});

  final File file;
  Future<void> _pendingWrite = Future<void>.value();

  static Future<PhotoFavoritesStore> inApplicationSupportDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/homeserver');
    await directory.create(recursive: true);
    return PhotoFavoritesStore(file: File('${directory.path}/photo-favorites.json'));
  }

  Future<Set<String>> load() async {
    if (!await file.exists()) return <String>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const FormatException('Invalid photo favourites data.');
    }
    return decoded.cast<String>().toSet();
  }

  Future<void> save(Set<String> favorites) {
    final snapshot = favorites.toList()..sort();
    final write = _pendingWrite.catchError((_) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot), flush: true);
      await temporary.rename(file.path);
    });
    _pendingWrite = write;
    return write;
  }
}
