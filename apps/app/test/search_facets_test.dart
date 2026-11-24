import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart' show KomgaUrls;
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/search_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// SCH-02：搜索筛选（阅读状态 + 标签）。作者筛选被服务端静默忽略，因此不做。
void main() {
  test('tag 参数写进查询串', () {
    final urls = KomgaUrls('http://x');
    final url = urls.series(search: 'frieren', tag: 'Sci Fi');
    expect(url, anyOf(contains('tag=Sci+Fi'), contains('tag=Sci%20Fi')));
    expect(url, contains('search=frieren'));
    expect(urls.series(), isNot(contains('tag=')));
  });

  late FakeLibraryRepository repository;

  Future<void> pumpSearch(WidgetTester tester) async {
    repository = FakeLibraryRepository(
      series: <Series>[
        const Series(
          id: 'tag-s1',
          libraryId: 'l1',
          title: 'Frieren',
          booksCount: 3,
          tags: <String>['Action', 'Fantasy'],
        ),
        const Series(
          id: 'tag-s2',
          libraryId: 'l1',
          title: 'Vagabond',
          booksCount: 2,
          tags: <String>['Action'],
        ),
      ],
    );
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
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
    // 'n' 同时命中 Frieren 与 Vagabond，标签聚合才拿得到两个。
    await tester.enterText(find.byType(TextField), 'n');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  testWidgets('阅读状态筛选会带到服务端，清除后回到无筛选', (WidgetTester tester) async {
    await pumpSearch(tester);

    expect(find.byKey(const Key('search-facets')), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-facet-unread')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(repository.lastSeriesReadStatus, SeriesReadStatus.unread);

    await tester.tap(find.byKey(const Key('search-facets-clear')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    // 不加筛选的查询实例会被缓存复用、不会重发请求，所以断言 UI 回到无筛选态。
    expect(find.byKey(const Key('search-facets-clear')), findsNothing);
  });

  testWidgets('标签 chip 来自结果聚合，可筛选也可取消', (WidgetTester tester) async {
    await pumpSearch(tester);

    expect(find.byKey(const Key('search-facet-tag-Action')), findsOneWidget);
    expect(find.byKey(const Key('search-facet-tag-Fantasy')), findsOneWidget);

    final actionChip = find.byKey(const Key('search-facet-tag-Action'));
    await tester.ensureVisible(actionChip);
    await tester.pumpAndSettle();
    await tester.tap(actionChip);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(repository.lastSeriesTag, 'Action');

    // 再点一次取消（布局可能因筛选变化而横向滚动，重新滚进视野再点）。
    await tester.ensureVisible(actionChip);
    await tester.pumpAndSettle();
    await tester.tap(actionChip);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-facets-clear')), findsNothing);
  });

  testWidgets('筛选胶囊横向滚动区不裁切阴影（Clip.none），避免真机圆角外露方形硬边', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byKey(const Key('search-facets')),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scrollView.clipBehavior, Clip.none);
  });
}
