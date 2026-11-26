import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/screens/history_screen.dart';
import 'package:yomu/src/widgets/recent_history_row.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// HIS-02：阅读历史页（按天分组、删除单条、清空、空态）。
void main() {
  late ProgressDatabase db;

  Future<void> seed() async {
    Future<void> add(String bookId, DateTime startedAt, {int minutes = 12}) {
      return db.addReadingSession(
        bookId: bookId,
        seriesId: 's1',
        bookName: 'Vol. $bookId',
        startedAt: startedAt,
        endedAt: startedAt.add(Duration(minutes: minutes)),
        durationMs: minutes * 60 * 1000,
        startPage: 1,
        endPage: 9,
        completed: false,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    await add('b1', today);
    await add('b2', today.add(const Duration(hours: 2)));
    await add('b3', today.subtract(const Duration(days: 1, hours: -1)));
  }

  Future<ProviderContainer> pumpHistory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/history',
      routes: <RouteBase>[
        GoRoute(
          path: '/history',
          builder: (BuildContext context, GoRouterState state) =>
              const HistoryScreen(),
        ),
        GoRoute(
          path: '/reader/:bookId',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('reader')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          ...testSourceOverrides(
            library: FakeLibraryRepository(series: demoShelf()),
          ),
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
    return ProviderScope.containerOf(
      tester.element(find.byType(HistoryScreen)),
    );
  }

  setUp(() => db = ProgressDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('按天分组显示：今天两条 + 昨天一条', (WidgetTester tester) async {
    await seed();
    await pumpHistory(tester);

    expect(find.byKey(const Key('history-group-Today')), findsOneWidget);
    expect(find.byKey(const Key('history-group-Yesterday')), findsOneWidget);
    expect(find.text('Vol. b1'), findsOneWidget);
    expect(find.text('Vol. b3'), findsOneWidget);
    // 时长与页码写在副标题里。
    expect(find.textContaining('p. 1–9'), findsNWidgets(3));
    expect(find.textContaining('12m 00s'), findsNWidgets(3));
  });

  testWidgets('删除单条', (WidgetTester tester) async {
    await seed();
    await pumpHistory(tester);

    await tester.tap(find.byKey(const Key('history-delete-1')));
    await tester.pumpAndSettle();

    expect(find.text('Vol. b1'), findsNothing);
    expect((await db.readingSessionList()).length, 2);
  });

  testWidgets('清空：确认后全没了，回到空态', (WidgetTester tester) async {
    await seed();
    await pumpHistory(tester);

    await tester.tap(find.byKey(const Key('history-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-ok')));
    await tester.pumpAndSettle();

    expect(await db.readingSessionList(), isEmpty);
    expect(find.text('No reading history yet'), findsOneWidget);
  });

  testWidgets('没有历史时是引导空态', (WidgetTester tester) async {
    await pumpHistory(tester);

    expect(find.text('No reading history yet'), findsOneWidget);
    expect(find.textContaining('read for a while'), findsOneWidget);
  });

  testWidgets('搜索会过滤列表', (WidgetTester tester) async {
    await seed();
    await pumpHistory(tester);

    await tester.enterText(find.byType(TextField), 'b2');
    await tester.pumpAndSettle();
    expect(find.text('Vol. b2'), findsOneWidget);
    expect(find.text('Vol. b1'), findsNothing);
  });

  Future<void> seedLocalBook(String bookId, String title) async {
    await db.insertImportedLocalBook(
      LocalBookImportDraft(
        bookId: bookId,
        seriesTitle: title,
        bookName: title,
        storageKind: 'cbz',
        relativePath: 'books/$bookId/book.cbz',
        sizeBytes: 1024,
        pages: const <ArchivePageEntry>[
          ArchivePageEntry(
            number: 1,
            entryName: '01.jpg',
            uncompressedSize: 100,
            compressedSize: 80,
            localHeaderOffset: 0,
            compressionMethod: 0,
          ),
        ],
      ),
      generateSeriesId: () => 'local:s_$bookId',
    );
  }

  testWidgets('本机漫画删除后：保留会话统计，历史页标记已移除且不可点击，支持一键清理', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await seedLocalBook('local:b_keep', 'Alive Local');
    await seedLocalBook('local:b_gone', 'Deleted Local');

    await db.addReadingSession(
      scope: kLocalSourceKey,
      bookId: 'local:b_keep',
      seriesId: 'local:s_local:b_keep',
      bookName: 'Alive Local',
      startedAt: today,
      endedAt: today.add(const Duration(minutes: 5)),
      durationMs: 5 * 60 * 1000,
      startPage: 1,
      endPage: 4,
      completed: false,
    );
    await db.addReadingSession(
      scope: kLocalSourceKey,
      bookId: 'local:b_gone',
      seriesId: 'local:s_local:b_gone',
      bookName: 'Deleted Local',
      startedAt: today.add(const Duration(hours: 1)),
      endedAt: today.add(const Duration(hours: 1, minutes: 8)),
      durationMs: 8 * 60 * 1000,
      startPage: 1,
      endPage: 6,
      completed: false,
    );

    // 删除本机书籍：按策略 B，reading_sessions 仍保留以维持阅读统计。
    await db.deleteLocalBookFromDb('local:b_gone');
    final container = await pumpHistory(tester);
    final sessions = await container.read(readingSessionsProvider.future);
    expect(sessions.length, 2);

    // 已移除条目展示 Removed 标记，且点击不会跳转进阅读器。
    expect(find.text('Deleted Local'), findsOneWidget);
    expect(find.textContaining('Removed'), findsOneWidget);
    await tester.tap(find.text('Deleted Local'));
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsNothing);

    // 仍存在的本机书籍点击可正常进入阅读器。
    await tester.tap(find.text('Alive Local'));
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('阅读历史菜单“清理已移除条目”仅删除孤儿本机记录', (WidgetTester tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await seedLocalBook('local:b_keep', 'Alive Local');
    await db.addReadingSession(
      scope: kLocalSourceKey,
      bookId: 'local:b_keep',
      seriesId: 'local:s_local:b_keep',
      bookName: 'Alive Local',
      startedAt: today,
      endedAt: today.add(const Duration(minutes: 5)),
      durationMs: 5 * 60 * 1000,
      startPage: 1,
      endPage: 4,
      completed: false,
    );
    await db.addReadingSession(
      scope: kLocalSourceKey,
      bookId: 'local:b_orphan',
      seriesId: 'local:s_orphan',
      bookName: 'Orphan Local',
      startedAt: today.add(const Duration(minutes: 30)),
      endedAt: today.add(const Duration(minutes: 40)),
      durationMs: 10 * 60 * 1000,
      startPage: 1,
      endPage: 8,
      completed: false,
    );

    await pumpHistory(tester);
    expect(find.text('Orphan Local'), findsOneWidget);
    expect(find.text('Alive Local'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-removed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-removed-ok')));
    await tester.pumpAndSettle();

    expect(find.text('Orphan Local'), findsNothing);
    expect(find.text('Alive Local'), findsOneWidget);
    final remaining = await db.readingSessionList();
    expect(remaining.map((ReadingSession s) => s.bookId), <String>[
      'local:b_keep',
    ]);
  });

  testWidgets('RecentHistoryRow 自动过滤已删除的本机漫画，全被过滤时隐藏整个区块', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await seedLocalBook('local:b_alive', 'Alive Local');
    await db.addReadingSession(
      scope: kLocalSourceKey,
      bookId: 'local:b_alive',
      seriesId: 'local:s_local:b_alive',
      bookName: 'Alive Local',
      startedAt: today,
      endedAt: today.add(const Duration(minutes: 5)),
      durationMs: 5 * 60 * 1000,
      startPage: 1,
      endPage: 4,
      completed: false,
    );
    await db.addReadingSession(
      scope: kLocalSourceKey,
      bookId: 'local:b_deleted',
      seriesId: 'local:s_deleted',
      bookName: 'Deleted Local',
      startedAt: today.add(const Duration(hours: 1)),
      endedAt: today.add(const Duration(hours: 1, minutes: 5)),
      durationMs: 5 * 60 * 1000,
      startPage: 1,
      endPage: 4,
      completed: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          ...testSourceOverrides(
            library: FakeLibraryRepository(series: demoShelf()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const Scaffold(body: RecentHistoryRow()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recent-history')), findsOneWidget);
    expect(find.text('Alive Local'), findsOneWidget);
    expect(find.text('Deleted Local'), findsNothing);

    // 再把仅存的本机书也删掉，RecentHistoryRow 自动隐藏。
    await db.deleteLocalBookFromDb('local:b_alive');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recent-history')), findsNothing);
  });
}
