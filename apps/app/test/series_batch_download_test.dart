import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';

/// SER-03：系列批量下载入队（跳过已下载 / 不重复 / 可取消）。
void main() {
  late _BatchDownloadService service;
  late HttpCacheDatabase db;
  late ProviderContainer container;

  setUp(() {
    service = _BatchDownloadService();
    db = HttpCacheDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: <Override>[
        downloadServiceProvider.overrideWithValue(service),
        httpCacheDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    container.read(downloadsProvider);
  });

  Book book(int i, {bool completed = false}) => Book(
    id: 'b$i',
    seriesId: 's1',
    name: 'Vol. $i',
    number: '$i',
    pagesCount: 3,
    sizeBytes: 100,
    readProgress: completed
        ? ReadProgress(
            page: 3,
            completed: true,
            lastModified: DateTime.utc(2026, 1, 1),
          )
        : null,
  );

  test('全部入队：逐本下载，完成后清空队列', () async {
    final result = await container.read(downloadsProvider.notifier).startMany(
      <Book>[book(1), book(2), book(3)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(result.queued, 3);
    expect(result.skipped, 0);
    expect(service.downloadedIds, <String>['b1', 'b2', 'b3']);
    expect(await db.downloadQueue(), isEmpty, reason: '下完就该清掉队列行');
  });

  test('已下载过的跳过，并如实回报跳过数量', () async {
    service.alreadyDownloaded.add('b2');

    final result = await container.read(downloadsProvider.notifier).startMany(
      <Book>[book(1), book(2), book(3)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(result.queued, 2);
    expect(result.skipped, 1);
    expect(service.downloadedIds, <String>['b1', 'b3']);
  });

  test('同一本重复提交不会下两次', () async {
    final notifier = container.read(downloadsProvider.notifier);
    final books = <Book>[book(1), book(2)];

    await notifier.startMany(books);
    await notifier.startMany(books);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.downloadedIds, <String>['b1', 'b2']);
  });

  test('取消这批：排队中的不再下载', () async {
    final notifier = container.read(downloadsProvider.notifier);
    service.gate = Completer<void>();

    unawaited(notifier.startMany(<Book>[book(1), book(2), book(3)]));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    notifier.cancelMany(<String>['b1', 'b2', 'b3']);
    service.gate?.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.cancelled, contains('b1'));
    expect(service.downloadedIds.length, lessThan(3));
    expect(await db.downloadQueue(), isEmpty);
  });
}

class _BatchDownloadService implements DownloadService {
  final Set<String> alreadyDownloaded = <String>{};
  final List<String> downloadedIds = <String>[];
  final List<String> cancelled = <String>[];
  Completer<void>? gate;

  @override
  Future<DownloadedBook?> downloaded(String bookId) async =>
      alreadyDownloaded.contains(bookId)
      ? DownloadedBook(
          scope: '',
          bookId: bookId,
          seriesId: 's1',
          bookName: bookId,
          pageCount: 3,
          bytes: 100,
          savedAt: DateTime.utc(2026, 1, 1),
        )
      : null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    await gate?.future;
    onProgress(const DownloadProgress(done: 3, total: 3));
    downloadedIds.add(book.id);
    // 真实实现会把记录写进 Drift；假实现也要让 downloaded() 之后返回非空，
    // 否则"已下载跳过"这条规则在测试里根本没被验证。
    alreadyDownloaded.add(book.id);
    return true;
  }

  @override
  Future<void> delete(Book book) async => downloadedIds.remove(book.id);

  @override
  void cancel(String bookId) => cancelled.add(bookId);
}
