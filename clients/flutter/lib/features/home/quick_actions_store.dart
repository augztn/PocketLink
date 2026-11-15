import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QuickActionsStore {
  QuickActionsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'home_quick_actions';
  static const defaults = ['files', 'photos', 'music', 'drives'];
  static const available = [
    'files',
    'photos',
    'music',
    'videos',
    'drives',
    'documents',
    'transfers',
  ];

  final FlutterSecureStorage _storage;

  Future<List<String>> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null) return List.of(defaults);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List.of(defaults);
      final saved = decoded.whereType<String>()
          .where(available.contains).toSet().toList();
      return saved.isEmpty ? List.of(defaults) : saved;
    } catch (_) {
      return List.of(defaults);
    }
  }

  Future<void> save(List<String> actions) async {
    final valid = actions.where(available.contains).toSet().toList();
    await _storage.write(key: storageKey, value: jsonEncode(valid));
  }
}
