import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// DLD-02：队列的暂停/继续、重试失败、取消。
void main() {
  late _QueueService service;
  late FakeLibraryRepository repository;
  late HttpCacheDatabase db;
  late ProviderContainer container;

  Book book(int i) => Book(
    id: 'b$i',
    seriesId: 's1',
    name: 'Vol. $i',
    number: '$i',
    pagesCount: 3,
    sizeBytes: 10,
  );

  setUp(() async {
    service = _QueueService();
    repository = FakeLibraryRepository(series: demoShelf());
    db = HttpCacheDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: <Override>[
        ...testSourceOverrides(library: repository, download: service),
        httpCacheDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    container.read(downloadsProvider);
    await Future<void>.delayed(Duration.zero);
  });

  test('暂停后不再启动新的，继续后把队列放出来', () async {
    final controller = container.read(downloadsProvider.notifier);
    service.hold = true;

    unawaited(controller.start(book(1)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.started, <String>['b1']);

    controller.pauseAll();
    expect(controller.paused, isTrue);

    unawaited(controller.start(book(2)));
    unawaited(controller.start(book(3)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.started, <String>['b1'], reason: '暂停中不启动新的');

    controller.resumeAll();
    expect(controller.paused, isFalse);
    // 并发默认 1：b1 还卡着时继续也不会多开。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.started, <String>['b1']);

    // 放行之后队列里的 b2、b3 依次补位。
    service.releaseAll();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.finished, containsAll(<String>['b1', 'b2', 'b3']));
  });

  test('重试失败项：只重排错误态的书', () async {
    final controller = container.read(downloadsProvider.notifier);
    service.failOnce.add('b1');

    await controller.start(book(1));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(service.finished, isEmpty);
    expect(
      container.read(downloadsProvider)['b1']?.errorKind,
      isNotNull,
      reason: '失败要留在列表里，否则没东西可重试',
    );

    final queued = await controller.retryFailed();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(queued, 1);
    expect(service.finished, <String>['b1'], reason: '第二次成功');
    expect(container.read(downloadsProvider)['b1'], isNull);
  });

  test('取消全部后不再下载', () async {
    final controller = container.read(downloadsProvider.notifier);
    service.hold = true;

    unawaited(controller.start(book(1)));
    unawaited(controller.start(book(2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.started, <String>['b1']);

    controller.cancelAll();
    service.releaseAll();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(service.started.length, lessThan(2));
    expect(container.read(downloadsProvider), isEmpty);
  });
}

class _QueueService implements DownloadService {
  final List<String> started = <String>[];
  final List<String> finished = <String>[];
  final Set<String> failOnce = <String>{};
  final Map<String, Completer<void>> _gates = <String, Completer<void>>{};
  final Set<String> cancelled = <String>{};

  /// true 时每次下载都挂在 gate 上，等测试显式放行。
  bool hold = false;
  bool _open = false;

  void releaseAll() {
    _open = true;
    for (final gate in _gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    started.add(book.id);
    if (hold && !_open) {
      await _gates.putIfAbsent(book.id, Completer<void>.new).future;
    }
    if (cancelled.contains(book.id)) return false;
    if (failOnce.remove(book.id)) {
      throw const UnexpectedFailure('boom');
    }
    onProgress(const DownloadProgress(done: 3, total: 3));
    finished.add(book.id);
    return true;
  }

  @override
  Future<void> delete(Book book) async {}

  @override
  void cancel(String bookId) => cancelled.add(bookId);
}
