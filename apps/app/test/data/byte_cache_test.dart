import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/byte_cache.dart';

Uint8List bytes(int value) => Uint8List.fromList(<int>[value]);

void main() {
  group('ByteLruCache', () {
    test('存进去能取出来，且命中计数增加', () {
      final cache = ByteLruCache(capacity: 4)..put('a', bytes(1));

      expect(cache.get('a'), bytes(1));
      expect(cache.hits, 1);
      expect(cache.misses, 0);
    });

    test('未命中返回 null 并计数（封面失败不该抛异常）', () {
      final cache = ByteLruCache();
      expect(cache.get('nope'), isNull);
      expect(cache.misses, 1);
    });

    test('超出容量时淘汰最久未使用的（LRU 而不是 FIFO）', () {
      final cache = ByteLruCache(capacity: 2)
        ..put('a', bytes(1))
        ..put('b', bytes(2));

      // 用一下 a，让 b 变成"最久未使用"。
      expect(cache.get('a'), bytes(1));

      cache.put('c', bytes(3));

      expect(cache.get('a'), bytes(1), reason: '刚用过，应保留');
      expect(cache.get('b'), isNull, reason: '最久未使用，应被淘汰');
      expect(cache.get('c'), bytes(3));
      expect(cache.length, 2);
    });

    test('同一个 key 重复 put 不会撑大缓存', () {
      final cache = ByteLruCache(capacity: 2)
        ..put('a', bytes(1))
        ..put('a', bytes(2));

      expect(cache.length, 1);
      expect(cache.get('a'), bytes(2));
    });

    test('clear 清空', () {
      final cache = ByteLruCache()
        ..put('a', bytes(1))
        ..clear();
      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
    });
  });
}
