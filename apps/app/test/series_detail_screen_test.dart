import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';

void main() {
  Future<void> pumpDetail(
    WidgetTester tester,
    FakeLibraryRepository repository, {
    String seriesId = 's1',
    Size logicalSize = const Size(390, 844),
  }) async {
    tester.view.physicalSize = Size(
      logicalSize.width * 3,
      logicalSize.height * 3,
    );
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/series/$seriesId',
      routes: <RouteBase>[
        GoRoute(
          path: '/series/:seriesId',
          builder: (BuildContext context, GoRouterState state) =>
              SeriesDetailScreen(
                seriesId: state.pathParameters['seriesId'] ?? '',
              ),
        ),
        GoRoute(
          path: '/reader/:bookId',
          builder: (BuildContext context, GoRouterState state) {
            final extra = state.extra;
            final args = extra is ReaderArgs ? extra : null;
            return ReaderScreen(
              bookId: state.pathParameters['bookId'] ?? '',
              book: args?.book,
              direction: args?.direction ?? ReadingDirection.leftToRight,
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
          readerRepositoryProvider.overrideWithValue(
            FakeReaderRepository(pageCount: 21),
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
  }

  testWidgets('头部显示系列信息，列表显示书', (WidgetTester tester) async {
    await pumpDetail(tester, FakeLibraryRepository(series: demoShelf()));
    await tester.pumpAndSettle();

    expect(find.text('Frieren'), findsWidgets);
    expect(find.text('5 of 12 read'), findsOneWidget);
    expect(find.textContaining('Vol. 1'), findsOneWidget);
    expect(find.textContaining('Vol. 6'), findsOneWidget);
  });

  testWidgets('已读完的书显示对勾与 Read 标记', (WidgetTester tester) async {
    await pumpDetail(tester, FakeLibraryRepository(series: demoShelf()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Read · '), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('空系列显示空态', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf())
      ..bookCount = 0;
    await pumpDetail(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-empty')), findsOneWidget);
  });

  testWidgets('加载失败显示错误并可重试', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      booksFailure: const NetworkFailure(),
    );
    await pumpDetail(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-error')), findsOneWidget);
    expect(find.text('Cannot reach the server'), findsOneWidget);

    repository.booksFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vol. 1'), findsOneWidget);
  });

  testWidgets('点一本书进入阅读器（带着书对象，不显示裸 id）', (WidgetTester tester) async {
    await pumpDetail(tester, FakeLibraryRepository(series: demoShelf()));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Vol. 3'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('Vol. 3'), findsWidgets);
    expect(find.text('1 / 21'), findsWidgets, reason: '阅读器应显示真实页数');
  });

  testWidgets('读完返回会刷新系列进度（不能在真机上显示 0 of N）', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf());
    await pumpDetail(tester, repository);
    await tester.pumpAndSettle();
    final before = repository.booksCalls;

    await tester.tap(find.textContaining('Vol. 3'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(repository.booksCalls, greaterThan(before), reason: '返回后应重新拉书列表');
    expect(repository.seriesByIdCalls, greaterThan(1), reason: '系列信息也要刷新');
  });

  testWidgets('宽屏（≥1024）是两栏：左头部、右书列表', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      FakeLibraryRepository(series: demoShelf()),
      logicalSize: const Size(1024, 768),
    );
    await tester.pumpAndSettle();

    // 头部信息在左栏，书行在右栏：两者的水平中心必须明显分开。
    final header = tester.getRect(find.text('5 of 12 read'));
    final book = tester.getRect(find.byKey(const Key('book-s1-b1')));
    expect(header.center.dx, lessThan(1024 * 0.5));
    expect(book.center.dx, greaterThan(1024 * 0.5));
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
  });

  testWidgets('手机宽度仍是单栏（头部在书列表上方）', (WidgetTester tester) async {
    await pumpDetail(tester, FakeLibraryRepository(series: demoShelf()));
    await tester.pumpAndSettle();

    final header = tester.getRect(find.text('5 of 12 read'));
    final book = tester.getRect(find.byKey(const Key('book-s1-b1')));
    expect(header.center.dy, lessThan(book.center.dy));
  });
}
