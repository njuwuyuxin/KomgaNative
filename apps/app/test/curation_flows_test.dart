import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/collection_detail_screen.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/screens/readlist_detail_screen.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:yomu/src/widgets/series_hero_tag.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    FakeLibraryRepository repository,
    Widget home,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
          httpCacheDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('收藏集完整操作闭环', () {
    testWidgets('系列页顶栏收藏按钮：将系列勾选加入已有收藏集', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(series: demoShelf());
      // s3 初始不在 c1（c1 只有 s1, s2）
      await pumpApp(tester, repo, const SeriesDetailScreen(seriesId: 's3'));

      await tester.tap(find.byKey(const Key('series-collection-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collection-picker-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('collection-pick-c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-picker-save')));
      await tester.pumpAndSettle();

      expect(repo.updatedCollectionSeries['c1'], <String>['s1', 's2', 's3']);
    });

    testWidgets('书架多选系列 → 批量条加入收藏集', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(
        series: demoShelf(),
        libraries: demoLibraries(),
      );
      await pumpApp(tester, repo, const LibraryScreen());

      await tester.tap(find.byKey(const Key('shelf-select-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-s3')));
      await tester.tap(find.byKey(const Key('series-s4')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shelf-batch-collection')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('collection-pick-c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-picker-save')));
      await tester.pumpAndSettle();

      expect(
        repo.updatedCollectionSeries['c1'],
        containsAll(<String>['s1', 's2', 's3', 's4']),
      );
      expect(find.text('Added 2 books to collection'), findsOneWidget);
    });

    testWidgets('中文环境下书架多选加入收藏集弹出明确提示文案', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(
        series: demoShelf(),
        libraries: demoLibraries(),
      );
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryRepositoryProvider.overrideWithValue(repo),
            httpCacheDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shelf-select-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-s3')));
      await tester.tap(find.byKey(const Key('series-s4')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shelf-batch-collection')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('collection-pick-c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-picker-save')));
      await tester.pumpAndSettle();

      expect(find.text('已将 2 本书加入收藏集'), findsOneWidget);
    });

    testWidgets('收藏集详情：移出系列 + 撤销恢复，以及移出最后一个时确认删除', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(series: demoShelf());
      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final router = GoRouter(
        initialLocation: '/collections/c1',
        routes: <RouteBase>[
          GoRoute(
            path: '/collections',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: Text('Collections root')),
          ),
          GoRoute(
            path: '/collections/:id',
            builder: (BuildContext context, GoRouterState state) =>
                CollectionDetailScreen(
                  collectionId: state.pathParameters['id']!,
                  title: 'Reading order',
                ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryRepositoryProvider.overrideWithValue(repo),
            httpCacheDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 移出 s2（剩余 s1）
      await tester.tap(find.byKey(const Key('collection-remove-s2')));
      await tester.pumpAndSettle();
      expect(repo.updatedCollectionSeries['c1'], <String>['s1']);

      // 点击 Undo 恢复
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.updatedCollectionSeries['c1'], <String>['s1', 's2']);

      // 依次移出 s2，再移出最后一个 s1 → 弹确认框并删除收藏集
      await tester.tap(find.byKey(const Key('collection-remove-s2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-remove-s1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('collection-remove-last-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('collection-remove-last-ok')));
      await tester.pumpAndSettle();

      expect(repo.deletedCollections, contains('c1'));
    });

    testWidgets('收藏集详情菜单：直接添加系列进当前收藏集', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(series: demoShelf());
      await pumpApp(
        tester,
        repo,
        const CollectionDetailScreen(
          collectionId: 'c1',
          title: 'Reading order',
        ),
      );

      await tester.tap(find.byKey(const Key('collection-detail-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-add-series')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('series-picker-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('series-pick-s3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-picker-confirm')));
      await tester.pumpAndSettle();

      expect(repo.updatedCollectionSeries['c1'], <String>['s1', 's2', 's3']);
    });
  });

  group('阅读列表完整操作闭环', () {
    testWidgets('系列页长按单本书 → 加入已有阅读列表 & 新建阅读列表', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(
        series: demoShelf(),
        ondeck: demoOndeck(),
      );
      await pumpApp(tester, repo, const SeriesDetailScreen(seriesId: 's1'));

      // 长按第 3 本（不在 r1 中）
      await tester.longPress(find.byKey(const Key('book-s1-b3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to read list'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readlist-picker-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('readlist-pick-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readlist-picker-save')));
      await tester.pumpAndSettle();

      expect(
        repo.updatedReadLists['r1']?.bookIds,
        containsAll(<String>['s1-b1', 's5-b2', 's1-b3']),
      );

      // 再次打开（选第 1 本，避开底部刚弹出的 SnackBar）并在面板内新建阅读列表
      await tester.longPress(find.byKey(const Key('book-s1-b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to read list'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('readlist-picker-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('readlist-create-name')),
        'Trip list',
      );
      await tester.enterText(
        find.byKey(const Key('readlist-create-summary')),
        'For flight',
      );
      await tester.tap(find.byKey(const Key('readlist-create-ok')));
      await tester.pumpAndSettle();

      expect(repo.createdReadLists, hasLength(1));
      expect(repo.createdReadLists.single.name, 'Trip list');
      expect(repo.createdReadLists.single.summary, 'For flight');
      expect(repo.createdReadLists.single.bookIds, <String>['s1-b1']);
    });

    testWidgets('系列页多选多本书 → 批量条加入阅读列表', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(
        series: demoShelf(),
        ondeck: demoOndeck(),
      );
      await pumpApp(tester, repo, const SeriesDetailScreen(seriesId: 's1'));

      await tester.tap(find.byKey(const Key('series-books-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-s1-b2')));
      await tester.ensureVisible(find.byKey(const Key('book-s1-b3')));
      await tester.tap(find.byKey(const Key('book-s1-b3')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('books-batch-readlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readlist-pick-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readlist-picker-save')));
      await tester.pumpAndSettle();

      expect(
        repo.updatedReadLists['r1']?.bookIds,
        containsAll(<String>['s1-b1', 's5-b2', 's1-b2', 's1-b3']),
      );
      expect(find.text('Added 2 books to read list'), findsOneWidget);
    });

    testWidgets('阅读列表详情：移出书 + 撤销恢复 + 移出最后一本书时确认删除', (
      WidgetTester tester,
    ) async {
      final repo = FakeLibraryRepository(
        series: demoShelf(),
        ondeck: demoOndeck(),
      );
      await pumpApp(
        tester,
        repo,
        const ReadListDetailScreen(readListId: 'r1', title: 'Weekend reading'),
      );

      await tester.tap(find.byKey(const Key('readlist-remove-s5-b2')));
      await tester.pumpAndSettle();
      expect(repo.updatedReadLists['r1']?.bookIds, <String>['s1-b1']);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.updatedReadLists['r1']?.bookIds, <String>['s1-b1', 's5-b2']);

      // 移出 s5-b2 再移出最后一本书 s1-b1 → 确认删除阅读列表
      await tester.tap(find.byKey(const Key('readlist-remove-s5-b2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readlist-remove-s1-b1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('readlist-remove-last-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('readlist-remove-last-ok')));
      await tester.pumpAndSettle();

      expect(repo.deletedReadLists, contains('r1'));
    });

    testWidgets('阅读列表 Tab：长按编辑与删除', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(
        series: demoShelf(),
        ondeck: demoOndeck(),
      );
      await pumpApp(tester, repo, const CollectionsScreen());

      await tester.tap(find.text('Read lists'));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('readlist-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readlist-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('readlist-name-field')),
        'Holiday list',
      );
      await tester.tap(find.byKey(const Key('readlist-form-ok')));
      await tester.pumpAndSettle();

      expect(repo.updatedReadLists['r1']?.name, 'Holiday list');
    });

    testWidgets('收藏集详情的系列 Hero 带独立作用域且只包裹封面', (WidgetTester tester) async {
      final repo = FakeLibraryRepository(series: demoShelf());
      await pumpApp(
        tester,
        repo,
        const CollectionDetailScreen(
          collectionId: 'c1',
          title: 'Reading order',
        ),
      );

      final scoped = seriesHeroTag('s1', scope: 'collection-c1');
      final heroFinder = find.byWidgetPredicate(
        (Widget w) => w is Hero && w.tag == scoped,
      );
      expect(heroFinder, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is Hero && w.tag == seriesHeroTag('s1'),
        ),
        findsNothing,
        reason: '不能与书架默认 tag 撞车，否则进出收藏集时会与隐藏书架乱飞',
      );
      final heroRect = tester.getRect(heroFinder);
      expect(
        heroRect.width,
        lessThan(100),
        reason: 'Hero 只包裹缩略图封面，不能包裹整行导致与详情页封面变形错位',
      );
    });
  });
}
