import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/history_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// HIS-02：阅读历史页（按天分组、删除单条、清空、空态）。
void main() {
  late HttpCacheDatabase db;

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
          httpCacheDatabaseProvider.overrideWithValue(db),
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository(series: demoShelf()),
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

  setUp(() => db = HttpCacheDatabase(NativeDatabase.memory()));
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
}
