import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/network/protected_file_cache.dart';

void main() {
  test('reopening updates LRU order without extending the expiry', () {
    var now = DateTime(2026);
    final cache = ProtectedFileCache(
      maxBytes: 4,
      maxFileBytes: 4,
      ttl: const Duration(minutes: 1),
      now: () => now,
    );
    cache.put('a', Uint8List.fromList([1, 2]));
    cache.put('b', Uint8List.fromList([3, 4]));
    expect(cache.get('a'), [1, 2]);
    cache.put('c', Uint8List.fromList([5, 6]));
    expect(cache.get('b'), isNull);
    expect(cache.get('a'), [1, 2]);
    now = now.add(const Duration(minutes: 1));
    expect(cache.get('a'), isNull);
    expect(cache.get('c'), isNull);
  });

  test('large files bypass cache and replacements respect the byte limit', () {
    final cache = ProtectedFileCache(maxBytes: 4, maxFileBytes: 3);
    cache.put('large', Uint8List(4));
    expect(cache.get('large'), isNull);
    cache.put('a', Uint8List.fromList([1, 2]));
    cache.put('a', Uint8List.fromList([3]));
    cache.put('b', Uint8List.fromList([4, 5, 6]));
    expect(cache.get('a'), [3]);
    expect(cache.get('b'), [4, 5, 6]);
    cache.clear();
    expect(cache.get('a'), isNull);
    expect(cache.get('b'), isNull);
  });
}
