import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/screens/search_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// SCH-03：搜索结果分页（加载更多）、切换查询不串、失败保留旧结果。
void main() {
  late FakeLibraryRepository repository;
  late ProviderContainer container;

  List<Series> manySeries(String prefix, int count) => <Series>[
    for (var i = 0; i < count; i++)
      Series(
        id: '$prefix-s$i',
        libraryId: 'l1',
        title: '$prefix series $i',
        booksCount: 1,
      ),
  ];

  Future<void> pumpSearch(WidgetTester tester, List<Series> series) async {
    repository = FakeLibraryRepository(series: series);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testSourceOverrides(library: repository),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  /// 往下拖到目标出现为止（SliverList 是懒构建的，不滚就找不到 footer）。
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -600),
        warnIfMissed: false,
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  test('分页：65 条能靠 PagedListController 增量 page=0,1,2 全部拿到且不重拉第 0 页', () async {
    repository = FakeLibraryRepository(series: manySeries('alpha', 65));
    container = ProviderContainer(
      overrides: testSourceOverrides(library: repository),
    );
    addTearDown(container.dispose);

    const query = (query: 'alpha', readStatus: null, tag: null);
    final first = await container.read(searchSeriesProvider(query).future);
    expect(first.items.length, 30);

    await container.read(searchSeriesProvider(query).notifier).loadMore();
    expect(container.read(searchSeriesProvider(query)).value!.items.length, 60);

    await container.read(searchSeriesProvider(query).notifier).loadMore();
    final all = container.read(searchSeriesProvider(query)).value!.items;
    expect(all.length, 65, reason: '最后不足一页时按实际条数追加');
    expect(repository.seriesCalls.map((c) => c.page).toList(), <int>[
      0,
      1,
      2,
    ], reason: '只请求增量页 0, 1, 2，不重拉第 0 页');
  });

  testWidgets('切换查询不会串结果', (WidgetTester tester) async {
    await pumpSearch(tester, <Series>[
      ...manySeries('alpha', 2),
      ...manySeries('beta', 2),
    ]);

    await search(tester, 'alpha');
    expect(find.text('alpha series 0'), findsOneWidget);

    await search(tester, 'beta');
    expect(find.text('beta series 0'), findsOneWidget);
    expect(find.text('alpha series 0'), findsNothing);
  });

  testWidgets('翻页失败时保留已有结果并提示', (WidgetTester tester) async {
    await pumpSearch(tester, manySeries('alpha', 40));
    await search(tester, 'alpha');
    expect(find.text('alpha series 0'), findsOneWidget);

    // 让后续请求失败，再滚到底点"加载更多"。
    repository.seriesFailure = const NetworkFailure();
    final footer = find.byKey(const Key('load-more'));
    await scrollTo(tester, footer);
    expect(footer.first, findsOneWidget);

    await tester.tap(footer.first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // 旧结果还在（没有被清空成错误页），顶部多一条提示。
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, 6000),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-refresh-failure')), findsOneWidget);
    expect(find.text('alpha series 0'), findsOneWidget);
  });
}
