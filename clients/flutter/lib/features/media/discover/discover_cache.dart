import 'package:flutter/foundation.dart';

/// Process-local discovery cache. Stale values remain readable while callers
/// refresh them in the background.
class DiscoverCache {
  DiscoverCache({
    this.ttl = const Duration(minutes: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final DiscoverCache instance = DiscoverCache();

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, DiscoverCacheEntry<Object?>> _entries = {};

  DiscoverCacheEntry<T>? read<T>(String key) {
    final entry = _entries[key];
    if (entry == null || entry.value is! T) return null;
    return DiscoverCacheEntry<T>(entry.value as T, entry.updatedAt);
  }

  void write<T>(String key, T value) {
    _entries[key] = DiscoverCacheEntry<Object?>(value, _clock());
  }

  bool isStale<T>(DiscoverCacheEntry<T> entry) =>
      _clock().difference(entry.updatedAt) >= ttl;

  @visibleForTesting
  void clear() => _entries.clear();
}

@immutable
class DiscoverCacheEntry<T> {
  const DiscoverCacheEntry(this.value, this.updatedAt);

  final T value;
  final DateTime updatedAt;
}
