import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// SER-01：系列内书列表的排序与筛选（只上线验证过的排序）。
void main() {
  late FakeLibraryRepository repository;

  Future<void> pumpSeries(WidgetTester tester, {int bookCount = 4}) async {
    repository = FakeLibraryRepository(series: demoShelf().take(1).toList())
      ..bookCount = bookCount;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: SeriesDetailScreen(seriesId: demoShelf().first.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('工具条显示总本数', (WidgetTester tester) async {
    await pumpSeries(tester);

    expect(find.byKey(const Key('series-books-toolbar')), findsOneWidget);
    final count = tester.widget<Text>(
      find.byKey(const Key('series-books-count')),
    );
    expect(count.data, '4 books');
  });

  testWidgets('按卷号降序：请求带 sort，数据顺序反过来', (WidgetTester tester) async {
    await pumpSeries(tester);

    await tester.tap(find.byKey(const Key('series-books-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-sort-number-desc')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(repository.lastBooksSort, BooksSort.numberDesc);
    // 行本身是懒构建的（在小屏上未必进视口），顺序直接查数据层。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SeriesDetailScreen)),
    );
    final page = container
        .read(
          seriesBooksProvider((
            sourceKey: null,
            seriesId: demoShelf().first.id,
            sort: BooksSort.numberDesc,
            readStatus: null,
          )),
        )
        .value;
    expect(page?.items.map((Book b) => b.name).toList(), <String>[
      'Vol. 4',
      'Vol. 3',
      'Vol. 2',
      'Vol. 1',
    ]);
  });
  testWidgets('筛选未读：请求带 read_status，条数跟着筛选变', (WidgetTester tester) async {
    await pumpSeries(tester);

    await tester.tap(find.byKey(const Key('series-books-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-filter-unread')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(repository.lastBooksReadStatus, SeriesReadStatus.unread);
    // fake 里第 1 本在读、第 2 本已读 → 未读只剩 2 本。
    expect(
      tester.widget<Text>(find.byKey(const Key('series-books-count'))).data,
      '2 books',
    );
    expect(find.byKey(const Key('series-books-clear')), findsOneWidget);
  });

  testWidgets('筛到空结果时给出"没有符合筛选的书"，清除后恢复', (WidgetTester tester) async {
    await pumpSeries(tester, bookCount: 1);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('series-books-filter')));
    await tester.pumpAndSettle();
    // 只有 1 本且它是在读 → 筛"已读"就是空结果。
    await tester.tap(find.byKey(const Key('series-filter-read')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-empty')), findsOneWidget);
    expect(find.text('No books match this filter'), findsOneWidget);

    // 清除筛选回到不带筛选的查询：那个 family 实例有缓存，不会再发请求。
    await tester.ensureVisible(find.byKey(const Key('series-books-clear')));
    await tester.tap(find.byKey(const Key('series-books-clear')));
    await tester.pumpAndSettle();
    expect(find.text('No books match this filter'), findsNothing);
    expect(find.byKey(const Key('series-empty')), findsNothing);
  });
}
