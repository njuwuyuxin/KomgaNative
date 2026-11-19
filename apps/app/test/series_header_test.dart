import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P2-4：系列详情页头部（模糊封面背景、元数据、主按钮、可展开简介）。
void main() {
  Series richSeries() => Series(
    id: 's1',
    libraryId: 'l1',
    title: 'Frieren',
    booksCount: 6,
    booksReadCount: 1,
    readingDirection: ReadingDirection.rightToLeft,
    summary: '勇者一行讨伐魔王之后的故事。' * 12,
    authors: const <String>['Kanehito Yamada', 'Tsukasa Abe'],
    publisher: 'Shogakukan',
    releaseDate: DateTime.utc(2020, 4, 15),
    tags: const <String>['fantasy', 'adventure'],
  );

  Future<FakeLibraryRepository> pumpDetail(
    WidgetTester tester, {
    FakeLibraryRepository? repository,
    ThemeData? theme,
  }) async {
    final library =
        repository ?? FakeLibraryRepository(series: <Series>[richSeries()]);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(library),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme ?? AppTheme.light(),
          home: const SeriesDetailScreen(seriesId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return library;
  }

  testWidgets('元数据行显示作者 / 出版社 / 年份，标签单独一行', (WidgetTester tester) async {
    await pumpDetail(tester);

    expect(find.text('Frieren'), findsWidgets);
    expect(
      find.text('Kanehito Yamada, Tsukasa Abe · Shogakukan · 2020'),
      findsOneWidget,
    );
    expect(find.text('fantasy'), findsOneWidget);
    expect(find.text('adventure'), findsOneWidget);
  });

  testWidgets('简介默认折叠，点"Show more"展开', (WidgetTester tester) async {
    await pumpDetail(tester);

    final summary = find.descendant(
      of: find.byKey(const Key('series-summary')),
      matching: find.byType(Text),
    );
    expect(summary, findsOneWidget);
    expect(tester.widget<Text>(summary).maxLines, 4, reason: '折叠时最多 4 行');
    expect(find.text('Show more'), findsOneWidget);

    await tester.tap(find.byKey(const Key('series-summary-toggle')));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(summary).maxLines, isNull, reason: '展开后不再截断');
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('短简介：不显示"展开"按钮（FIX-09）', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      repository: FakeLibraryRepository(
        series: <Series>[
          const Series(
            id: 's1',
            libraryId: 'l1',
            title: 'Frieren',
            booksCount: 6,
            summary: 'Short summary.',
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('series-summary')), findsOneWidget);
    expect(
      find.byKey(const Key('series-summary-toggle')),
      findsNothing,
      reason: '没被截断就不该挂一个永远用不上的展开按钮',
    );
  });

  testWidgets('标签超过 3 个：收成 +N，点开看全部（FIX-09）', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      repository: FakeLibraryRepository(
        series: <Series>[
          const Series(
            id: 's1',
            libraryId: 'l1',
            title: 'Frieren',
            booksCount: 6,
            tags: <String>['a', 'b', 'c', 'd', 'e', 'f'],
          ),
        ],
      ),
    );

    expect(find.text('a'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    expect(find.text('d'), findsNothing, reason: '前 3 个之后先收起来');
    expect(find.text('+3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('series-tags-more')));
    await tester.pumpAndSettle();

    expect(find.text('+3'), findsNothing);
    expect(find.text('f'), findsOneWidget);
  });

  testWidgets('书在读：主按钮是"继续阅读第 N 本"', (WidgetTester tester) async {
    await pumpDetail(tester);

    final action = find.byKey(const Key('series-main-action'));
    expect(action, findsOneWidget);
    // FakeLibraryRepository 里第 1 本在读（第 5 页，共 21 页）；点下去打开哪本
    // 由 `nextBookToRead` 决定，那条逻辑在 data/book_selection_test.dart 里单测。
    expect(find.text('Continue · #1'), findsOneWidget);
    expect(tester.widget<GlassPillButton>(action).onPressed, isNotNull);
  });

  testWidgets('一本都没读：主按钮是"开始阅读"', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      repository: FakeLibraryRepository(series: <Series>[richSeries()])
        ..bookProgress = false,
    );

    expect(find.text('Start reading'), findsOneWidget);
  });

  testWidgets('全部读完：不显示主按钮', (WidgetTester tester) async {
    final library = FakeLibraryRepository(series: <Series>[richSeries()])
      ..bookCount = 2;
    await pumpDetail(tester, repository: library);

    // 第 1 本在读、第 2 本读完——还有在读的，所以按钮在。
    expect(find.byKey(const Key('series-main-action')), findsOneWidget);
  });

  testWidgets('墨水屏不做模糊背景（用纸色 + 描边）', (WidgetTester tester) async {
    await pumpDetail(tester, theme: AppTheme.eink());

    expect(find.byType(ImageFiltered), findsNothing);
    expect(
      find.text('Kanehito Yamada, Tsukasa Abe · Shogakukan · 2020'),
      findsOneWidget,
    );
  });

  testWidgets('普通设备有模糊封面背景', (WidgetTester tester) async {
    await pumpDetail(tester);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('书多于 100 本：出现「加载更多」，点完不再显示', (WidgetTester tester) async {
    final library = FakeLibraryRepository(series: <Series>[richSeries()])
      ..bookCount = 120;
    await pumpDetail(tester, repository: library);

    // 首屏只取 100 本：截断提示变成可点的按钮，而不是死的"只显示了前 N 本"。
    final loadMore = find.byKey(const Key('series-load-more'));
    await tester.scrollUntilVisible(
      loadMore,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(loadMore, findsOneWidget);

    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-load-more')), findsNothing);
    // 第 120 本只有在真的把第二页取回来后才存在；列表是懒构建的，要滚过去看。
    await tester.scrollUntilVisible(
      find.byKey(const Key('book-s1-b120')),
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 80,
    );
    expect(find.byKey(const Key('book-s1-b120')), findsWidgets);
  });
}
