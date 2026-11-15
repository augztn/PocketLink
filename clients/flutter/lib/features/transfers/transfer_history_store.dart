import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class TransferHistoryStore {
  TransferHistoryStore({required this.file});

  final File file;
  Future<void> _pendingWrite = Future<void>.value();

  static Future<TransferHistoryStore> inApplicationSupportDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/homeserver');
    await directory.create(recursive: true);
    return TransferHistoryStore(
      file: File('${directory.path}/transfer-history.json'),
    );
  }

  Future<List<Map<String, dynamic>>> load() async {
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('Invalid transfer history data.');
    }
    return decoded.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Invalid transfer history entry.');
      }
      return Map<String, dynamic>.from(entry);
    }).toList(growable: false);
  }

  Future<void> save(List<Map<String, dynamic>> entries) {
    final snapshot = jsonEncode(entries);
    final write = _pendingWrite.catchError((_) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    _pendingWrite = write;
    return write;
  }
}
