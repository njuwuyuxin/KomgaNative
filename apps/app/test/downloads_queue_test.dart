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

import 'support/test_source_overrides.dart';

/// UI-P3-13：下载队列一次只跑一本，后面的显示"排队中"。
void main() {
  test('两本书依次下载：第二本先排队，第一本完成后才开始', () async {
    final service = _QueueDownloadService();
    final container = ProviderContainer(
      overrides: <Override>[
        ...testSourceOverrides(download: service),
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(downloadsProvider.notifier);

    final first = controller.start(_book('b1'));
    await _drain();
    final second = controller.start(_book('b2'));
    await _drain();

    expect(service.order, <String>['b1']);
    expect(container.read(downloadsProvider)['b1']?.isRunning, isTrue);
    expect(container.read(downloadsProvider)['b2']?.queued, isTrue);

    service.first.complete(true);
    await first;
    await second;

    expect(service.order, <String>['b1', 'b2']);
    expect(container.read(downloadsProvider), isEmpty);
  });

  group('队列持久化（FIX-07）', () {
    test('杀进程重启：队列恢复并自动接着下', () async {
      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 第一次运行：开始下载，卡在"下载中"，然后进程"死掉"。
      final first = _BlockingDownloadService();
      final firstContainer = ProviderContainer(
        overrides: <Override>[
          ...testSourceOverrides(download: first),
          httpCacheDatabaseProvider.overrideWithValue(db),
        ],
      );
      final starting = firstContainer
          .read(downloadsProvider.notifier)
          .start(_book('b1'));
      await _drain();
      expect(first.order, <String>['b1']);
      expect(
        (await db.downloadQueue(scope: kTestKomgaSourceKey)).single.bookId,
        'b1',
      );
      firstContainer.dispose();

      // 重启：同一个库，新的 service。应当自动恢复并下完。
      final second = _OkDownloadService();
      final secondContainer = ProviderContainer(
        overrides: <Override>[
          ...testSourceOverrides(download: second),
          httpCacheDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(secondContainer.dispose);
      secondContainer.read(downloadsProvider);
      await _drain();
      await _drain();

      expect(second.order, <String>['b1'], reason: '重启后自动接着下');
      expect(secondContainer.read(downloadsProvider), isEmpty);
      expect(
        await db.downloadQueue(scope: kTestKomgaSourceKey),
        isEmpty,
        reason: '下完要把队列行删掉',
      );

      // 第一次那个 future 不会再完成，但也不能留下未捕获异常。
      starting.ignore();
    });

    test('已经下载完的书不会因为残留队列行被重下', () async {
      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.markDownloaded(
        scope: kTestKomgaSourceKey,
        bookId: 'b1',
        seriesId: 's1',
        pageCount: 3,
        bytes: 100,
      );
      await db.enqueueDownload(
        scope: kTestKomgaSourceKey,
        bookId: 'b1',
        seriesId: 's1',
        name: 'b1',
        number: '',
        pagesCount: 3,
      );

      final service = _QueueDownloadService();
      final container = ProviderContainer(
        overrides: <Override>[
          ...testSourceOverrides(download: service),
          httpCacheDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      container.read(downloadsProvider);
      await _drain();

      expect(service.order, isEmpty);
      expect(
        await db.downloadQueue(scope: kTestKomgaSourceKey),
        isEmpty,
        reason: '残留行要清掉',
      );
      expect(container.read(downloadsProvider), isEmpty);
    });

    test('取消全部：清空排队、取消进行中、磁盘上的队列也清掉', () async {
      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _BlockingDownloadService();
      final container = ProviderContainer(
        overrides: <Override>[
          ...testSourceOverrides(download: service),
          httpCacheDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(downloadsProvider.notifier);

      final running = controller.start(_book('b1'));
      await _drain();
      final queued = controller.start(_book('b2'));
      await _drain();
      expect(service.order, <String>['b1']);

      controller.cancelAll();
      await _drain();

      expect(service.cancelled, containsAll(<String>['b1', 'b2']));
      expect(container.read(downloadsProvider), isEmpty);
      expect(await db.downloadQueue(scope: kTestKomgaSourceKey), isEmpty);
      running.ignore();
      queued.ignore();
    });
  });
}

Future<void> _drain() async {
  // drift 的写入要穿过事件循环（不是纯微任务），6 轮够用但不多——
  // 新加的队列持久化会多排几次写，这里给足余量避免偶发。
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Book _book(String id) => Book(id: id, seriesId: 's1', name: id, pagesCount: 3);

class _QueueDownloadService implements DownloadService {
  final List<String> order = <String>[];
  final List<String> cancelled = <String>[];
  final Completer<bool> first = Completer<bool>();

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) {
    order.add(book.id);
    onProgress(const DownloadProgress(done: 0, total: 1));
    if (order.length == 1) return first.future;
    onProgress(const DownloadProgress(done: 1, total: 1));
    return Future<bool>.value(true);
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  void cancel(String bookId) => cancelled.add(bookId);

  @override
  Future<void> delete(Book book) async {}
}

/// 立刻下完的下载：重启后"自动接着下"用它，避免被 first.future 挂住。
class _OkDownloadService implements DownloadService {
  final List<String> order = <String>[];
  final List<String> cancelled = <String>[];

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    order.add(book.id);
    onProgress(const DownloadProgress(done: 1, total: 3));
    return true;
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  void cancel(String bookId) => cancelled.add(bookId);

  @override
  Future<void> delete(Book book) async {}
}

/// 永远下不完的下载：用来模拟"进程在下载中途被杀掉"。
class _BlockingDownloadService implements DownloadService {
  final List<String> order = <String>[];
  final List<String> cancelled = <String>[];

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) {
    order.add(book.id);
    onProgress(const DownloadProgress(done: 0, total: 3));
    return Completer<bool>().future;
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  void cancel(String bookId) => cancelled.add(bookId);

  @override
  Future<void> delete(Book book) async {}
}
