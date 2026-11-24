import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/discover/discover_cache.dart';

void main() {
  test('retains cached data for immediate display after the TTL expires', () {
    var now = DateTime(2026, 11, 24, 12);
    final cache = DiscoverCache(
      ttl: const Duration(minutes: 20),
      clock: () => now,
    );
    cache.write('moods:IN', <String>['Focus', 'Sleep']);

    final entry = cache.read<List<String>>('moods:IN')!;
    expect(entry.value, ['Focus', 'Sleep']);
    expect(cache.isStale(entry), isFalse);

    now = now.add(const Duration(minutes: 21));
    expect(cache.isStale(entry), isTrue);
    expect(cache.read<List<String>>('moods:IN')?.value, ['Focus', 'Sleep']);
  });

  test('does not return cache data under a different type', () {
    final cache = DiscoverCache();
    cache.clear();
    cache.write('home:IN', <String>['Trending']);
    expect(cache.read<int>('home:IN'), isNull);
  });
}
