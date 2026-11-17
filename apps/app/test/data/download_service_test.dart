import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 整本下载：进度、幂等、取消、失败、删除。
void main() {
  const scope = 'https://komga.example.com';
  late HttpCacheDatabase db;

  Book book({String id = 'b1', int pages = 3}) => Book(
    id: id,
    seriesId: 's1',
    name: 'Vol. 1',
    number: '1',
    pagesCount: pages,
  );

  KomgaDownloadService build({
    int pages = 3,
    int byteSize = 10,
    Set<int> failAt = const <int>{},
    void Function(int page)? onPage,
  }) {
    return KomgaDownloadService(
      pages: (String bookId) async => <PageInfo>[
        for (var i = 1; i <= pages; i++)
          PageInfo(number: i, width: 800, height: 1200, mediaType: 'image/png'),
      ],
      pageImage: (String bookId, int page) async {
        onPage?.call(page);
        if (failAt.contains(page)) throw const NetworkFailure();
        return Uint8List(byteSize);
      },
      db: db,
      scope: scope,
    );
  }

  setUp(() {
    db = HttpCacheDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('下载整本：进度从 0 到 total，完成后记录页数与字节数', () async {
    final progress = <DownloadProgress>[];
    final service = build(byteSize: 100);

    final done = await service.download(book(), onProgress: progress.add);

    expect(done, isTrue);
    expect(progress.first.done, 0);
    expect(progress.last.done, 3);
    expect(progress.last.total, 3);
    expect(progress.last.fraction, 1.0);

    final record = await service.downloaded('b1');
    expect(record, isNotNull);
    expect(record!.pageCount, 3);
    expect(record.bytes, 300);
  });

  test('已下载的书再下载：返回 false，且不再抓页（幂等）', () async {
    var calls = 0;
    final service = build(onPage: (_) => calls++);
    await service.download(book(), onProgress: (_) {});

    calls = 0;
    final again = await service.download(book(), onProgress: (_) {});

    expect(again, isFalse);
    expect(calls, 0);
  });

  test('取消：在页与页之间停止，不写下载记录', () async {
    late KomgaDownloadService service;
    final seen = <int>[];
    service = build(
      onPage: (int page) {
        seen.add(page);
        // 抓完第 2 页时用户点了取消。
        if (page == 2) service.cancel('b1');
      },
    );

    final done = await service.download(book(), onProgress: (_) {});

    expect(done, isFalse);
    expect(seen, <int>[1, 2]);
    expect(await service.downloaded('b1'), isNull);
  });

  test('中途失败：抛 ShelfFailure，不写下载记录', () async {
    final service = build(failAt: <int>{2});

    await expectLater(
      service.download(book(), onProgress: (_) {}),
      throwsA(isA<NetworkFailure>()),
    );
    expect(await service.downloaded('b1'), isNull);
  });

  test('删除：下载记录与已缓存页图一起清掉，不动别的书', () async {
    final service = build();
    await service.download(book(), onProgress: (_) {});
    for (final page in <int>[1, 2, 3]) {
      await db.write(
        scope,
        '$scope/api/v1/books/b1/pages/$page?zero_based=false',
        'image',
        Uint8List(4),
      );
    }
    await db.write(
      scope,
      '$scope/api/v1/books/b2/pages/1?zero_based=false',
      'image',
      Uint8List(4),
    );

    await service.delete(book());

    expect(await service.downloaded('b1'), isNull);
    expect(
      await db.read(scope, '$scope/api/v1/books/b1/pages/1?zero_based=false'),
      isNull,
    );
    expect(
      await db.read(scope, '$scope/api/v1/books/b2/pages/1?zero_based=false'),
      isNotNull,
    );
  });

  test('空页列表：返回 false，不写记录（避免"下载了 0 页"的假成功）', () async {
    final service = build(pages: 0);
    expect(await service.download(book(pages: 0), onProgress: (_) {}), isFalse);
    expect(await service.downloaded('b1'), isNull);
  });
}
