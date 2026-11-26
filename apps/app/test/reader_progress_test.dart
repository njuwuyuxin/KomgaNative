import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/drift_http_cache.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/screens/reading_now_screen.dart';
import 'package:yomu_sync/yomu_sync.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/fakes.dart';
import 'support/reader_harness.dart';

/// 阅读器与 outbox 的接缝：翻页必须先落本地，服务端能不能收到是第二件事。
void main() {
  testWidgets('断网翻页：进度先落本地，联网后补交', (WidgetTester tester) async {
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository(
      saveFailure: const NetworkFailure(),
    );
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      progressStore: progressStore,
    );

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));

    // 服务端没收到，但本地队列里有第 2 页。
    expect(repository.saved, isEmpty, reason: '断网时上传必然失败');
    final pending = await progressStore.pending();
    expect(pending, hasLength(1));
    expect(pending.single.target.page, 2);

    // 网络恢复：下一次翻页会顺带把积压的进度一起推上去。
    repository.saveFailure = null;
    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(await progressStore.pending(), isEmpty);
    // 同书只保留最新一条：补交的是第 3 页，而不是先补 2 再补 3。
    expect(
      repository.saved.map((({int page, bool completed}) s) => s.page),
      <int>[3],
    );
  });

  testWidgets('进度已落本地：即使上传失败，页码也不会回退', (WidgetTester tester) async {
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository(
      saveFailure: const NetworkFailure(),
    );
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      progressStore: progressStore,
    );

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('2 / 3'), findsOneWidget);

    // 本地记录已经是第 2 页，重建阅读器（模拟返回列表再进来）应停在这里。
    final record = await progressStore.record('b1');
    expect(record!.page, 2);
  });

  testWidgets('打开未读新书不翻页直接退出：自动记第 1 页在读，并联动刷新继续阅读', (
    WidgetTester tester,
  ) async {
    const unreadBook = Book(
      id: 'b-new',
      seriesId: 's1',
      seriesTitle: 'Frieren',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 12,
    );
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository(pageCount: 12);
    await pumpReader(
      tester,
      repository: repository,
      bookId: unreadBook.id,
      book: unreadBook,
      progressStore: progressStore,
    );

    // 停在第 1 页直接退出（销毁阅读器），不点下一页、不等 600ms。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(repository.saved, <({int page, bool completed})>[
      (page: 1, completed: false),
    ]);
    final record = await progressStore.record('b-new');
    expect(record?.page, 1);
    expect(record?.completed, isFalse);
  });

  testWidgets('翻页后未满 600ms 防抖立即退出：不会丢掉最后那一页', (WidgetTester tester) async {
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      progressStore: progressStore,
    );

    await tapRight(tester);
    // 防抖尚未触发就立刻退出阅读器。
    expect(repository.saved, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(repository.saved, <({int page, bool completed})>[
      (page: 2, completed: false),
    ]);
  });

  testWidgets('打开已读完的书不翻页直接退出：不覆盖原完成状态', (WidgetTester tester) async {
    final completedBook = Book(
      id: 'b-done',
      seriesId: 's1',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 3,
      readProgress: ReadProgress(
        page: 3,
        completed: true,
        lastModified: DateTime.utc(2026, 1, 1),
      ),
    );
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository: repository,
      bookId: completedBook.id,
      book: completedBook,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
  });

  testWidgets('打开未读新书开启隐身模式后退出：不写入任何进度', (WidgetTester tester) async {
    const unreadBook = Book(
      id: 'b-incog',
      seriesId: 's1',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 5,
    );
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository(pageCount: 5);
    await pumpReader(
      tester,
      repository: repository,
      bookId: unreadBook.id,
      book: unreadBook,
      progressStore: progressStore,
    );

    await tapReaderMenu(tester, 'reader-incognito-button');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
    expect(await progressStore.record('b-incog'), isNull);
  });

  testWidgets('从阅读器 pop 返回后无需下拉刷新，"正在读"自动出现刚打开的书', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const unread = Book(
      id: 's1-b1',
      seriesId: 's1',
      seriesTitle: 'Frieren',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 12,
    );
    final ondeckBooks = <Book>[];
    final library = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
      ondeck: ondeckBooks,
    );
    final readerRepo = FakeReaderRepository(pageCount: 12);
    final progressStore = InMemoryProgressStore();
    final sync = ProgressSyncService(
      store: progressStore,
      upload: (ProgressTarget target) async {
        await readerRepo.uploadProgress(
          target.bookId,
          page: target.page,
          completed: target.completed,
        );
        ondeckBooks
          ..clear()
          ..add(
            unread.withProgress(
              ReadProgress(
                page: target.page,
                completed: target.completed,
                lastModified: DateTime.utc(2026, 11, 20),
              ),
            ),
          );
      },
    );
    final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(cacheDb.close);
    final cache = DriftHttpCache(cacheDb);

    final router = GoRouter(
      initialLocation: '/reading',
      routes: <RouteBase>[
        GoRoute(
          path: '/reading',
          builder: (BuildContext context, GoRouterState state) =>
              const ReadingNowScreen(),
        ),
        GoRoute(
          path: '/reader/:bookId',
          builder: (BuildContext context, GoRouterState state) => ReaderScreen(
            bookId: state.pathParameters['bookId'] ?? '',
            book: unread,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(library),
          readerRepositoryProvider.overrideWithValue(readerRepo),
          progressSyncProvider.overrideWithValue(sync),
          readerPrefsStoreProvider.overrideWithValue(
            InMemoryReaderPrefsStore(),
          ),
          wakeLockProvider.overrideWithValue(FakeWakeLock()),
          hardwareKeysProvider.overrideWithValue(FakeHardwareKeys()),
          httpCacheProvider.overrideWithValue(cache),
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

    // 初始空态："Nothing in progress"
    expect(find.byKey(const Key('reading-now-empty')), findsOneWidget);

    // 打开未读新书，不翻页，直接返回"正在读"。
    unawaited(router.push('/reader/s1-b1'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reading-now-empty')), findsNothing);
    final card = find.byKey(const Key('reading-now-continue'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Vol. 1 · p. 1/12')),
      findsOneWidget,
    );
  });
}
