import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_toc_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// RDR-02：阅读器"目录"= 本系列的书列表，点一本替换当前页。
void main() {
  /// 24 本书的系列：用来验证"打开时定位到当前书"不是靠运气。
  FakeLibraryRepository booksRepository() {
    final repository = FakeLibraryRepository(series: demoShelf());
    repository.bookCount = 24;
    return repository;
  }

  Future<GoRouter> pumpSheet(
    WidgetTester tester, {
    required String currentBookId,
    FakeLibraryRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/reader/current',
      routes: <RouteBase>[
        GoRoute(
          path: '/reader/:bookId',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: Center(
              child: Text('reader:${state.pathParameters['bookId']}'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(
            repository ?? booksRepository(),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 从"当前页"里打开目录（真实入口是顶栏按钮）。
    final context = tester.element(find.text('reader:current'));
    unawaited(
      showReaderTocSheet(
        context,
        seriesId: 's1',
        currentBookId: currentBookId,
        palette: ReaderPalette.dark,
        direction: ReadingDirection.rightToLeft,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('列出系列里的书，当前这本高亮且标注"当前"', (WidgetTester tester) async {
    await pumpSheet(tester, currentBookId: 's1-b1');

    expect(find.byKey(const Key('reader-toc-list')), findsOneWidget);
    final current = find.byKey(const Key('reader-toc-book-s1-b1'));
    expect(current, findsOneWidget);
    expect(
      tester.widget<ListTile>(current).enabled,
      isFalse,
      reason: '点当前这本没有意义，直接禁用',
    );
    expect(find.textContaining('Current · '), findsOneWidget);
    // 别的书是可点的。
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-toc-book-s1-b2')))
          .enabled,
      isTrue,
    );
  });

  testWidgets('打开时滚到当前书（24 本里的第 20 本）', (WidgetTester tester) async {
    await pumpSheet(tester, currentBookId: 's1-b20');

    final current = find.byKey(const Key('reader-toc-book-s1-b20'));
    expect(current, findsOneWidget);
    // 在当前视口内：定位逻辑生效了（否则它还在屏幕外）。
    final rect = tester.getRect(current);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(844));
  });

  testWidgets('点另一本：替换当前页，返回栈不增长', (WidgetTester tester) async {
    final router = await pumpSheet(tester, currentBookId: 's1-b1');

    await tester.tap(find.byKey(const Key('reader-toc-book-s1-b2')));
    await tester.pumpAndSettle();

    expect(find.text('reader:s1-b2'), findsOneWidget);
    expect(
      router.canPop(),
      isFalse,
      reason: '换书必须 pushReplacement，连读十本不能压十层返回栈',
    );
  });
}
