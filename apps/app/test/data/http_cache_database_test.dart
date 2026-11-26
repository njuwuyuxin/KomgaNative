import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';

/// 内容缓存表的单测。
///
/// 重点不是"能存能取"（那是 Drift 的事），而是**淘汰策略**：
/// 图片按字节预算 LRU，JSON 不参与字节淘汰、只按条数上限裁剪。
void main() {
  late HttpCacheDatabase db;

  HttpCacheDatabase open({int maxImageBytes = 1000, int maxJsonRows = 3}) =>
      HttpCacheDatabase(
        NativeDatabase.memory(),
        maxImageBytes: maxImageBytes,
        maxJsonRows: maxJsonRows,
      );

  setUp(() {
    db = open();
  });

  tearDown(() async {
    await db.close();
  });

  Uint8List bytes(int length, [int fill = 1]) =>
      Uint8List(length)..fillRange(0, length, fill);

  group('读写', () {
    test('写入后可读回同一份字节，并记录类型与大小', () async {
      await db.write(
        'srv',
        'https://srv/api/v1/series?page=0',
        'json',
        bytes(10),
      );

      final row = await db.read('srv', 'https://srv/api/v1/series?page=0');

      expect(row, isNotNull);
      expect(row!.body, bytes(10));
      expect(row.kind, 'json');
      expect(row.byteSize, 10);
    });

    test('未命中返回 null', () async {
      expect(await db.read('srv', 'missing'), isNull);
    });

    test('同一 key 覆盖写，不产生第二行', () async {
      await db.write('srv', 'url', 'json', bytes(4));
      await db.write('srv', 'url', 'json', bytes(6));

      final usage = await db.usage();
      expect(usage.entries, 1);
      expect(usage.bytes, 6);
    });

    test('不同服务器分区互不可见', () async {
      await db.write('a', 'url', 'json', bytes(4));
      expect(await db.read('b', 'url'), isNull);
    });
  });

  group('图片按字节预算 LRU 淘汰', () {
    test('超出预算时淘汰最久未用的那条', () async {
      db = open(maxImageBytes: 1000);
      await db.write('s', 'a', 'image', bytes(400));
      await db.write('s', 'b', 'image', bytes(400));
      // 读一下 a：它变成"最近使用"，该被淘汰的是 b。
      expect(await db.read('s', 'a'), isNotNull);
      await db.write('s', 'c', 'image', bytes(400));

      expect(await db.read('s', 'b'), isNull);
      expect(await db.read('s', 'a'), isNotNull);
      expect(await db.read('s', 'c'), isNotNull);
    });

    test('单条超过预算也要能存（只是会立刻淘汰别人）', () async {
      db = open(maxImageBytes: 100);
      await db.write('s', 'huge', 'image', bytes(500));
      expect(await db.read('s', 'huge'), isNotNull);
    });
  });

  group('JSON 不参与字节淘汰', () {
    test('大量图片把预算挤爆后，JSON 仍然可读', () async {
      db = open(maxImageBytes: 500);
      await db.write('s', 'meta', 'json', bytes(80));
      for (var i = 0; i < 6; i++) {
        await db.write('s', 'img$i', 'image', bytes(300));
      }

      expect(await db.read('s', 'meta'), isNotNull);
      // 反向验证：图片确实被淘汰过，否则这条测试是空转。
      expect(await db.read('s', 'img0'), isNull);
    });

    test('JSON 条数超过上限时淘汰最旧的', () async {
      db = open(maxJsonRows: 3);
      for (var i = 0; i < 5; i++) {
        await db.write('s', 'json$i', 'json', bytes(10));
      }

      expect(await db.read('s', 'json0'), isNull);
      expect(await db.read('s', 'json1'), isNull);
      expect(await db.read('s', 'json4'), isNotNull);
      final usage = await db.usage(scope: 's');
      expect(usage.entries, 3);
    });
  });

  group('占用统计', () {
    test('合计字节与条数，可按服务器过滤', () async {
      await db.write('a', 'x', 'json', bytes(10));
      await db.write('a', 'y', 'image', bytes(20));
      await db.write('b', 'z', 'json', bytes(5));

      expect((await db.usage()).bytes, 35);
      expect((await db.usage()).entries, 3);
      expect((await db.usage(scope: 'a')).bytes, 30);
      expect((await db.usage(scope: 'a')).entries, 2);
    });

    test('humanSize 用最接近的单位', () {
      expect(const CacheUsage(bytes: 512, entries: 1).humanSize, '512 B');
      expect(const CacheUsage(bytes: 2048, entries: 1).humanSize, '2 KB');
      expect(
        const CacheUsage(bytes: 5 * 1024 * 1024, entries: 1).humanSize,
        '5.0 MB',
      );
    });

    test('空库是 isEmpty', () async {
      expect((await db.usage()).isEmpty, isTrue);
    });
  });

  group('清空', () {
    test('按服务器清空不影响别人', () async {
      await db.write('a', 'x', 'json', bytes(4));
      await db.write('b', 'y', 'json', bytes(4));

      await db.clear(scope: 'a');

      expect(await db.read('a', 'x'), isNull);
      expect(await db.read('b', 'y'), isNotNull);
    });

    test('全部清空', () async {
      await db.write('a', 'x', 'json', bytes(4));
      await db.write('b', 'y', 'image', bytes(4));

      await db.clear();

      expect((await db.usage()).isEmpty, isTrue);
    });
  });
}
