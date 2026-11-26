import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_view_options.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';

import '../support/fake_library.dart';
import '../support/fakes.dart';

/// 书架偏好的持久化（FIX-02）：视图/封面档位/排序/筛选/库筛选重启后还在，
/// 且换服务器不会带着上一台的库筛选。
void main() {
  const serverKey = 'https://komga.example.com';

  Future<void> settle() async {
    // 恢复链是"读存储 → （可能）查库列表 → 拉第一页"，多轮转几次。
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 建一个"已经连上服务器"的容器。
  ///
  /// 先等会话恢复完再建立书架订阅：真机上书架只在已连接时存在
  /// （`libraryRepositoryProvider` 在未连接时直接抛 StateError），
  /// 所以这里也照同样的顺序来，否则测的是一条不存在于产品的路径。
  Future<ProviderContainer> containerWith({
    required FakeLibraryRepository repository,
    required InMemorySettingsStore store,
  }) async {
    final container = ProviderContainer(
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
        settingsStoreProvider.overrideWithValue(store),
        serverStoreProvider.overrideWithValue(
          InMemoryServerStore(storedServer()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider);
    await settle();
    expect(container.read(sessionProvider), isA<SessionConnected>());

    final subscription = container.listen(
      shelfProvider,
      (ShelfState? _, ShelfState _) {},
    );
    addTearDown(subscription.close);
    return container;
  }

  test('冷启动恢复视图 / 封面档位 / 排序 / 筛选，并按恢复后的条件加载', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = await containerWith(
      repository: repository,
      store: InMemorySettingsStore(
        const AppSettings(
          view: ShelfView.list,
          coverSize: ShelfCoverSize.large,
          sort: SeriesSort.titleDesc,
          readStatus: SeriesReadStatus.unread,
        ),
      ),
    );
    await settle();

    final state = container.read(shelfProvider);
    expect(state.view, ShelfView.list);
    expect(state.coverSize, ShelfCoverSize.large);
    expect(state.sort, SeriesSort.titleDesc);
    expect(state.readStatus, SeriesReadStatus.unread);

    // 首屏不等偏好恢复（读钥匙串不能挡首帧），所以恢复后补了一次请求；
    // 关键是**最终**这次带着恢复的排序/筛选，列表顺序才对得上界面上的排序标记。
    expect(repository.seriesCalls.last.sort, SeriesSort.titleDesc);
    expect(repository.seriesCalls.last.readStatus, SeriesReadStatus.unread);
  });

  test('只恢复呈现方式（视图/封面档位）时不重新请求', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = await containerWith(
      repository: repository,
      store: InMemorySettingsStore(
        const AppSettings(
          view: ShelfView.list,
          coverSize: ShelfCoverSize.small,
        ),
      ),
    );
    await settle();

    expect(container.read(shelfProvider).view, ShelfView.list);
    expect(container.read(shelfProvider).coverSize, ShelfCoverSize.small);
    expect(repository.seriesCalls, hasLength(1));
  });

  test('改视图 / 封面档位 / 排序 / 筛选都会落盘', () async {
    final store = InMemorySettingsStore();
    final container = await containerWith(
      repository: FakeLibraryRepository(series: demoShelf()),
      store: store,
    );
    await settle();

    final controller = container.read(shelfProvider.notifier);
    controller.setView(ShelfView.list);
    controller.setCoverSize(ShelfCoverSize.small);
    controller.setSort(SeriesSort.recentlyAdded);
    controller.setReadStatus(SeriesReadStatus.read);
    await settle();

    expect(store.settings.view, ShelfView.list);
    expect(store.settings.coverSize, ShelfCoverSize.small);
    expect(store.settings.sort, SeriesSort.recentlyAdded);
    expect(store.settings.readStatus, SeriesReadStatus.read);
  });

  test('切库记住到当前服务器名下；再次启动恢复', () async {
    final store = InMemorySettingsStore();
    final repository = FakeLibraryRepository(
      libraries: demoLibraries(),
      series: demoShelf(),
    );
    final container = await containerWith(repository: repository, store: store);
    await settle();

    container.read(shelfProvider.notifier).selectLibrary('l2');
    await settle();

    expect(container.read(shelfProvider).libraryId, 'l2');
    expect(store.settings.libraryFilterFor(serverKey), 'l2');
    expect(store.settings.libraryFilters.keys, hasLength(1));

    // 新容器 = 冷启动：仍然停在上次那个库。
    final restarted = await containerWith(repository: repository, store: store);
    await settle();
    expect(restarted.read(shelfProvider).libraryId, 'l2');
    expect(repository.seriesCalls.last.libraryId, 'l2');
  });

  test('换服务器不携带上一台的库筛选', () async {
    final store = InMemorySettingsStore();
    await store.update(
      (AppSettings s) => s.withLibraryFilter('https://other.example', 'l9'),
    );

    final repository = FakeLibraryRepository(
      libraries: demoLibraries(),
      series: demoShelf(),
    );
    final container = await containerWith(repository: repository, store: store);
    await settle();

    expect(container.read(shelfProvider).libraryId, isNull);
    expect(repository.seriesCalls.single.libraryId, isNull);
  });

  test('存档里的库已经不存在：回到"全部库"并把脏记录清掉', () async {
    final store = InMemorySettingsStore();
    await store.update(
      (AppSettings s) => s.withLibraryFilter(serverKey, 'gone'),
    );

    final repository = FakeLibraryRepository(
      libraries: demoLibraries(),
      series: demoShelf(),
    );
    final container = await containerWith(repository: repository, store: store);
    await settle();

    expect(container.read(shelfProvider).libraryId, isNull);
    expect(repository.seriesCalls.single.libraryId, isNull);
    // 脏记录被清掉，下次启动不用再查一遍。
    expect(store.settings.libraryFilterFor(serverKey), isNull);
  });

  test('用户在恢复落地前就改了排序：不被存档覆盖', () async {
    final repository = FakeLibraryRepository(series: demoShelf());
    final container = await containerWith(
      repository: repository,
      store: InMemorySettingsStore(
        const AppSettings(sort: SeriesSort.titleDesc),
      ),
    );

    // 恢复还没落地，立刻手动换排序。
    container.read(shelfProvider.notifier).setSort(SeriesSort.recentlyAdded);
    await settle();

    expect(container.read(shelfProvider).sort, SeriesSort.recentlyAdded);
    expect(repository.seriesCalls.last.sort, SeriesSort.recentlyAdded);
  });
}
