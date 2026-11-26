import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/library_providers.dart';

import '../support/fake_library.dart';

/// 控制器里的加载是 fire-and-forget（`unawaited`），用微任务轮转把它推到完成。
Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  ProviderContainer containerWith(FakeLibraryRepository repository) {
    final container = ProviderContainer(
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    // 保持订阅：不订阅的话容器里的派生状态可能被回收。
    final subscription = container.listen(
      shelfProvider,
      (ShelfState? _, ShelfState _) {},
    );
    addTearDown(subscription.close);
    container.read(shelfProvider);
    return container;
  }

  test('首屏加载成功：loading → 有数据', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);

    expect(container.read(shelfProvider).loading, isTrue);

    await settle();

    final state = container.read(shelfProvider);
    expect(state.loading, isFalse);
    expect(state.series, hasLength(6));
    expect(state.totalElements, 6);
    expect(state.hasMore, isFalse);
    expect(state.failure, isNull);
  });

  test('换排序：带上 sort 重新拉第一页', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);
    await settle();

    container.read(shelfProvider.notifier).setSort(SeriesSort.titleDesc);
    await settle();

    final call = repository.seriesCalls.last;
    expect(call.sort, SeriesSort.titleDesc);
    expect(call.page, 0);
    expect(container.read(shelfProvider).sort, SeriesSort.titleDesc);
    expect(container.read(shelfProvider).loading, isFalse);
  });

  test('换阅读状态筛选：带上 readStatus，并保留排序与搜索词', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);
    await settle();

    container.read(shelfProvider.notifier).search('a');
    await Future<void>.delayed(ShelfController.searchDebounce);
    await settle();
    container.read(shelfProvider.notifier).setSort(SeriesSort.titleAsc);
    await settle();
    container
        .read(shelfProvider.notifier)
        .setReadStatus(SeriesReadStatus.unread);
    await settle();

    final call = repository.seriesCalls.last;
    expect(call.readStatus, SeriesReadStatus.unread);
    expect(call.sort, SeriesSort.titleAsc);
    expect(call.query, 'a');
    expect(container.read(shelfProvider).readStatus, SeriesReadStatus.unread);
  });

  test('恢复默认排序：sort 传 null（用服务端默认）', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);
    await settle();

    container.read(shelfProvider.notifier).setSort(SeriesSort.titleAsc);
    await settle();
    container.read(shelfProvider.notifier).setSort(null);
    await settle();

    expect(repository.seriesCalls.last.sort, isNull);
  });

  test('首屏失败：给出可重试的失败类型，不抛裸异常', () async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      seriesFailure: const NetworkFailure(),
    );
    final container = containerWith(repository);
    await settle();

    final state = container.read(shelfProvider);
    expect(state.failure, isA<NetworkFailure>());
    expect(state.series, isEmpty);
    expect(state.loading, isFalse);
  });

  test('失败后重试成功', () async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      seriesFailure: const NetworkFailure(),
    );
    final container = containerWith(repository);
    await settle();
    expect(container.read(shelfProvider).failure, isNotNull);

    repository.seriesFailure = null;
    await container.read(shelfProvider.notifier).refresh();

    final state = container.read(shelfProvider);
    expect(state.failure, isNull);
    expect(state.series, hasLength(6));
  });

  test('分页：第一页 30，追加后 45，到底后不再请求', () async {
    final repository = FakeLibraryRepository(series: manySeries(45));
    final container = containerWith(repository);
    await settle();

    expect(container.read(shelfProvider).series, hasLength(30));
    expect(container.read(shelfProvider).hasMore, isTrue);

    await container.read(shelfProvider.notifier).loadMore();

    final state = container.read(shelfProvider);
    expect(state.series, hasLength(45));
    expect(state.hasMore, isFalse);
    expect(repository.seriesCalls.map((c) => c.page), <int>[0, 1]);

    // 到底后再触发也不应该再发请求。
    await container.read(shelfProvider.notifier).loadMore();
    expect(repository.seriesCalls, hasLength(2));
  });

  test('追加失败：保留已加载内容，只在底部提示', () async {
    final repository = FakeLibraryRepository(series: manySeries(45));
    final container = containerWith(repository);
    await settle();

    repository.seriesFailure = const ServerFailure();
    await container.read(shelfProvider.notifier).loadMore();

    final state = container.read(shelfProvider);
    expect(state.series, hasLength(30), reason: '已加载的内容不能被清掉');
    expect(state.loadMoreFailure, isA<ServerFailure>());
    expect(state.failure, isNull);
  });

  test('下拉刷新失败：保留旧数据，不把整页打成错误态', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);
    await settle();

    repository.seriesFailure = const NetworkFailure();
    await container.read(shelfProvider.notifier).refresh();

    final state = container.read(shelfProvider);
    expect(state.series, hasLength(6));
    expect(state.failure, isNull);
    expect(state.loadMoreFailure, isA<NetworkFailure>());
  });

  test('搜索防抖：立刻更新关键词，350ms 后才发请求', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);
    await settle();
    expect(repository.seriesCalls, hasLength(1));

    container.read(shelfProvider.notifier).search('v');
    expect(container.read(shelfProvider).query, 'v');
    expect(repository.seriesCalls, hasLength(1), reason: '防抖期间不应发请求');

    await Future<void>.delayed(const Duration(milliseconds: 400));
    await settle();

    expect(repository.seriesCalls, hasLength(2));
    expect(repository.seriesCalls.last.query, 'v');
    expect(container.read(shelfProvider).series.map((s) => s.title), <String>[
      'Vagabond',
    ]);
  });

  test('按库筛选：切库清空旧列表并带上 libraryId', () async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    final container = containerWith(repository);
    await settle();

    container.read(shelfProvider.notifier).selectLibrary('l2');
    await settle();

    final state = container.read(shelfProvider);
    expect(state.libraryId, 'l2');
    expect(state.series.map((s) => s.title), <String>['Sunny', 'Pluto']);
    expect(repository.seriesCalls.last.libraryId, 'l2');
  });

  test('refreshInPlace：保留列表与滚动位置，静默换新数据', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = containerWith(repository);
    await settle();
    final callsBefore = repository.seriesCalls.length;

    final gate = Completer<void>();
    repository.gate = gate;
    final future = container.read(shelfProvider.notifier).refreshInPlace();
    await settle();

    // 请求还在飞：列表不能清空，也不能回到骨架屏状态。
    expect(container.read(shelfProvider).series, hasLength(6));
    expect(container.read(shelfProvider).loading, isFalse);

    gate.complete();
    await future;
    await settle();

    expect(container.read(shelfProvider).series, hasLength(6));
    expect(repository.seriesCalls.length, greaterThan(callsBefore));
  });

  test('竞态：旧请求后回来也不会覆盖新结果', () async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    final container = containerWith(repository);
    await settle();

    // 卡住后续请求，制造"两个请求同时在飞"的窗口。
    final gate = Completer<void>();
    repository.gate = gate;

    final oldRefresh = container.read(shelfProvider.notifier).refresh();
    container.read(shelfProvider.notifier).selectLibrary('l2');

    gate.complete();
    await oldRefresh;
    await settle();

    final state = container.read(shelfProvider);
    expect(state.libraryId, 'l2');
    expect(state.series.map((s) => s.title), <String>[
      'Sunny',
      'Pluto',
    ], reason: '旧请求（全部系列）不能盖掉新请求（Manga 库）的结果');
  });
}
