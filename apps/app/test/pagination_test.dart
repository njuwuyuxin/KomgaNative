import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/screens/collection_detail_screen.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:yomu/src/screens/readlist_detail_screen.dart';
import 'package:yomu/src/screens/search_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// FIX-08：收藏集 / 阅读列表 / 搜索以前固定只取 20 条，第 21 条起静默消失。
void main() {
  const total = 45;

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testSourceOverrides(library: _PagedRepository()),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 页脚在列表末尾：sliver 是懒构建的，不滚下去它根本不在树上。
  Future<void> revealFooter(WidgetTester tester) async {
    final footer = find.byKey(const Key('load-more'));
    for (var i = 0; i < 12 && footer.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(footer, findsOneWidget, reason: '滚到底应该看到"加载更多"');
  }

  testWidgets('收藏集：首屏一页 + "加载更多"，点完能看到全部', (WidgetTester tester) async {
    await pumpScreen(tester, const CollectionsScreen());

    await revealFooter(tester);
    expect(find.text('Showing 30 of $total'), findsOneWidget);

    // 收藏集页多了搜索行，页脚可能被顶到屏幕外——先确保它可见。
    await tester.ensureVisible(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();

    // 全部加载完：页脚消失，最后一本真的在列表里。
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('load-more')), findsNothing);
    expect(find.text('Collection $total'), findsOneWidget);
  });

  testWidgets('阅读列表：同样分页', (WidgetTester tester) async {
    await pumpScreen(tester, const CollectionsScreen());

    await tester.tap(find.text('Read lists'));
    await tester.pumpAndSettle();

    await revealFooter(tester);
    expect(find.text('Showing 30 of $total'), findsOneWidget);
  });

  testWidgets('阅读列表详情：长列表能加载更多', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const ReadListDetailScreen(readListId: 'r1', title: 'Weekend'),
    );

    await revealFooter(tester);
    expect(find.text('Showing 30 of $total books'), findsOneWidget);

    // 收藏集页多了搜索行，页脚可能被顶到屏幕外——先确保它可见。
    await tester.ensureVisible(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('load-more')), findsNothing);
  });

  testWidgets('收藏集详情：长列表能加载更多', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const CollectionDetailScreen(collectionId: 'c1', title: 'Reading'),
    );

    await revealFooter(tester);
    expect(find.text('Showing 30 of $total series'), findsOneWidget);

    // 收藏集页多了搜索行，页脚可能被顶到屏幕外——先确保它可见。
    await tester.ensureVisible(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('load-more')), findsNothing);
  });

  testWidgets('搜索：两个区块各自分页', (WidgetTester tester) async {
    await pumpScreen(tester, const SearchScreen());

    await tester.enterText(find.byKey(const Key('search-field')), 'Result');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 系列区块在书区块之前：滚到第一条页脚即可。
    await revealFooter(tester);
    await tester.tap(find.byKey(const Key('load-more')).first);
    await tester.pumpAndSettle();
    // 点一次把两个区块的 size 一起加大，页脚都消失。
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('load-more')), findsNothing);
  });
}

/// 分页假仓库：每个来源都给 45 条，并且**尊重 size**（默认的假仓库不切片，
/// 测不出"第 21 条起消失"这件事）。
class _PagedRepository extends FakeLibraryRepository {
  _PagedRepository()
    : super(
        series: demoShelf(),
        libraries: demoLibraries(),
        ondeck: demoOndeck(),
      );

  static const int _total = 45;

  List<Collection> get _collections => <Collection>[
    for (var i = 1; i <= _total; i++)
      Collection(
        id: 'c$i',
        name: 'Collection $i',
        ordered: false,
        seriesIds: const <String>[],
      ),
  ];

  List<ReadList> get _readLists => <ReadList>[
    for (var i = 1; i <= _total; i++)
      ReadList(
        id: 'r$i',
        name: 'List $i',
        summary: '',
        ordered: false,
        bookIds: const <String>[],
      ),
  ];

  List<Book> get _books => <Book>[
    for (var i = 1; i <= _total; i++)
      Book(id: 'b$i', seriesId: 's1', name: 'Result $i', pagesCount: 10),
  ];

  List<Series> get _series => <Series>[
    for (var i = 1; i <= _total; i++)
      Series(id: 's$i', libraryId: 'l1', title: 'Result $i', booksCount: 1),
  ];

  static PageResult<T> _page<T>(List<T> all, int page, int size) {
    final start = page * size;
    final items = start >= all.length
        ? <T>[]
        : all.sublist(start, math.min(start + size, all.length));
    return PageResult<T>(
      items: items,
      totalElements: all.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<PageResult<Collection>> collections({
    int page = 0,
    int size = 20,
  }) async => _page(_collections, page, size);

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) async =>
      _page(_readLists, page, size);

  @override
  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async => _page(_books, page, size);

  @override
  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async => _page(_series, page, size);

  @override
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) async => _page(_books, page, size);

  @override
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) async => _page(_series, page, size);
}
