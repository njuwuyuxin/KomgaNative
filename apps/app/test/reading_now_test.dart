import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reading_now_screen.dart';
import 'package:komga_native/src/screens/series_detail_args.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/src/widgets/book_hero_tag.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P2-6「正在读」首页：继续阅读卡片、最近添加、按库分组。
void main() {
  Future<FakeLibraryRepository> pumpPage(
    WidgetTester tester, {
    FakeLibraryRepository? repository,
    bool settle = true,
  }) async {
    final library =
        repository ??
        FakeLibraryRepository(
          series: demoShelf(),
          libraries: demoLibraries(),
          ondeck: demoOndeck(),
        );
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
          theme: AppTheme.light(),
          home: const ReadingNowScreen(),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return library;
  }

  testWidgets('大号继续阅读卡片：第一行系列名，第二行"卷号 · 页码"', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('reading-now-continue')), findsOneWidget);
    // demoOndeck 第一本属于 Frieren、读到第 5 页共 12 页（FIX-06）。
    // 用 descendant 限定在卡片内：货架里也有一张 "Frieren"。
    final card = find.byKey(const Key('reading-now-continue'));
    expect(
      find.descendant(of: card, matching: find.text('Frieren')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Vol. 1 · p. 5/12')),
      findsOneWidget,
    );
    expect(find.text('Continue reading'), findsOneWidget);
    // 封面是阅读器开场 Hero 的起点（UI-P2-2）。
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Hero && widget.tag == bookHeroTag('s1-b1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('最近添加与按库分组各有一条货架', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Comics'), findsOneWidget);
    // 系列卡片真的渲染出来了（不是空壳）。
    expect(find.byType(SeriesShelfTile), findsWidgets);

    // 第二个库的货架在首屏之外：sliver 不构建屏幕外的内容，得先滚下去。
    await tester.scrollUntilVisible(
      find.text('Manga'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Manga'), findsOneWidget);
  });

  testWidgets('没有在读的书：给一句说明，不摆空壳', (WidgetTester tester) async {
    await pumpPage(
      tester,
      repository: FakeLibraryRepository(
        series: demoShelf(),
        libraries: demoLibraries(),
        ondeck: const <Book>[],
      ),
    );

    expect(find.byKey(const Key('reading-now-empty')), findsOneWidget);
    expect(find.byKey(const Key('reading-now-continue')), findsNothing);
    expect(find.text('Nothing in progress'), findsOneWidget);
  });

  testWidgets('加载中先显示骨架，绝不先闪"没有在读的书"', (WidgetTester tester) async {
    final gate = Completer<void>();
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
      ondeck: demoOndeck(),
    )..ondeckGate = gate;

    await pumpPage(tester, repository: repository, settle: false);

    expect(
      find.byKey(const Key('reading-now-continue-skeleton')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reading-now-empty')), findsNothing);
    expect(find.byKey(const Key('reading-now-continue')), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reading-now-continue')), findsOneWidget);
    expect(find.byKey(const Key('reading-now-empty')), findsNothing);
  });

  testWidgets('首次加载失败：给错误提示与重试，不假装"没有在读的书"', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
      ondeck: demoOndeck(),
      ondeckFailure: const NetworkFailure(),
    );
    await pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('reading-now-error')), findsOneWidget);
    expect(find.byKey(const Key('reading-now-empty')), findsNothing);

    // 恢复后点重试：拿到真正的继续阅读卡。
    repository.ondeckFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reading-now-continue')), findsOneWidget);
    expect(find.byKey(const Key('reading-now-error')), findsNothing);
  });

  testWidgets('有内容时刷新失败：保留旧卡片 + 一行提示', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
      ondeck: demoOndeck(),
    );
    await pumpPage(tester, repository: repository);
    expect(find.byKey(const Key('reading-now-continue')), findsOneWidget);

    // 下一次请求失败，再触发一次刷新。
    repository.ondeckFailure = const NetworkFailure();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReadingNowScreen)),
    );
    container.invalidate(ondeckProvider);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reading-now-continue')),
      findsOneWidget,
      reason: '刷新失败不能把已有内容清掉',
    );
    expect(find.byKey(const Key('reading-now-refresh-failed')), findsOneWidget);
    expect(find.byKey(const Key('reading-now-error')), findsNothing);
  });

  testWidgets('列表失败时货架为空，但页面本身不报错', (WidgetTester tester) async {
    await pumpPage(
      tester,
      repository: FakeLibraryRepository(
        series: demoShelf(),
        libraries: demoLibraries(),
        ondeck: demoOndeck(),
      )..seriesFailure = const NetworkFailure(),
    );

    expect(find.byKey(const Key('reading-now-continue')), findsOneWidget);
    expect(find.byType(SeriesShelfTile), findsNothing);
  });

  testWidgets('同一系列出现在"最近添加"和按库货架时，Hero tag 不能重复', (WidgetTester tester) async {
    await pumpPage(tester);

    final tags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((Hero hero) => hero.tag)
        .toList();
    expect(tags, isNotEmpty);
    expect(
      tags.toSet(),
      hasLength(tags.length),
      reason:
          '同一路由里 tag 重复时 Flutter 只会挑其中一个 Hero，'
          '封面会从另一份的位置飞进来',
    );
  });

  testWidgets('点哪一份货架卡片，详情页就用那一份的 Hero tag', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    /// 在给定货架上点 s1，断言详情页头部与源卡片用同一个（带作用域的）tag。
    Future<void> check({required Key shelfKey, required String scope}) async {
      // 每轮都从空树开始：两轮之间换了 ProviderScope / GoRouter，避免复用旧树。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final repository = FakeLibraryRepository(
        series: demoShelf(),
        libraries: demoLibraries(),
        ondeck: demoOndeck(),
      );
      final router = GoRouter(
        initialLocation: '/reading',
        routes: <RouteBase>[
          GoRoute(
            path: '/reading',
            builder: (BuildContext context, GoRouterState state) =>
                const ReadingNowScreen(),
          ),
          GoRoute(
            path: '/series/:seriesId',
            builder: (BuildContext context, GoRouterState state) {
              final extra = state.extra;
              final args = extra is SeriesDetailArgs ? extra : null;
              return SeriesDetailScreen(
                seriesId: state.pathParameters['seriesId'] ?? '',
                heroTag: args?.heroTag,
              );
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryRepositoryProvider.overrideWithValue(repository),
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

      final source = find.descendant(
        of: find.byKey(shelfKey),
        matching: find.byKey(const Key('series-s1')),
      );
      expect(source, findsOneWidget);
      await tester.ensureVisible(source);
      await tester.pumpAndSettle();

      await tester.tap(source);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final tag = seriesHeroTag('s1', scope: scope);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is Hero && widget.tag == tag,
        ),
        findsNWidgets(2),
        reason:
            '$scope：源卡片与详情头部必须是同一个 tag，'
            '否则封面会从另一份的位置飞进来',
      );

      // 退出：飞回同一张卡片，页面回到"正在读"（飞行层没有 Material 祖先，
      // 卡片里的 InkWell 在 debug 下会断言，这条也顺带钉住）。
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-now-scroll')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is Hero && widget.tag == tag,
        ),
        findsOneWidget,
      );
    }

    await check(
      shelfKey: const Key('reading-now-recent'),
      scope: 'reading-now-recent',
    );
    await check(
      shelfKey: const Key('reading-now-library-l1'),
      scope: 'reading-now-library-l1',
    );
  });
}
