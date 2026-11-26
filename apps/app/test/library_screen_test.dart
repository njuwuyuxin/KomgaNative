import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// 书架页的界面行为：只验"状态 → 画面"和"操作 → 调用"，
/// 分页/防抖/竞态这些逻辑在 shelf_controller_test.dart 里单独测。
void main() {
  Future<void> pumpShelf(
    WidgetTester tester,
    FakeLibraryRepository repository,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: testSourceOverrides(library: repository),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const LibraryScreen(),
        ),
      ),
    );
  }

  /// 带 spinner 的状态不能用 pumpAndSettle（永远settle不下来）。
  Future<void> pumpFrames(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('排序菜单：选 Title Z-A 后把 sort 传下去并重排', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf());
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title Z-A'));
    await tester.pumpAndSettle();

    expect(repository.seriesCalls.last.sort, SeriesSort.titleDesc);
    // Z→A 时第一个系列是 Vagabond。
    expect(find.text('Vagabond'), findsOneWidget);
  });

  testWidgets('筛选菜单：选 Read 后只显示读完的系列', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf());
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();

    expect(repository.seriesCalls.last.readStatus, SeriesReadStatus.read);
    expect(find.text('Vagabond'), findsOneWidget);
    expect(find.text('Blame!'), findsNothing);
  });

  testWidgets('加载中先出骨架屏，不闪白屏', (WidgetTester tester) async {
    final gate = Completer<void>();
    final repository = FakeLibraryRepository(series: demoShelf())..gate = gate;

    await pumpShelf(tester, repository);
    await tester.pump();

    expect(find.byKey(const Key('shelf-skeleton')), findsOneWidget);
    expect(find.text('Frieren'), findsNothing);

    repository.gate = null;
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-skeleton')), findsNothing);
    expect(find.text('Frieren'), findsOneWidget);
  });

  testWidgets('渲染真实系列标题与封面，并显示总数', (WidgetTester tester) async {
    await pumpShelf(tester, FakeLibraryRepository(series: demoShelf()));
    await tester.pumpAndSettle();

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Vagabond'), findsOneWidget);
    expect(find.byType(Image), findsWidgets, reason: '有封面时应渲染图片');

    // 总数在网格底部（sliver 懒构建，不滚下去根本不在树里）。
    await tester.drag(
      find.byKey(const Key('shelf-scroll')),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    expect(find.text('6 series'), findsOneWidget);
  });

  testWidgets('失败态给出可重试的提示，点 Retry 后恢复', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      seriesFailure: const NetworkFailure(),
    );
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-error')), findsOneWidget);
    expect(find.text('Cannot reach the server'), findsOneWidget);

    repository.seriesFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-error')), findsNothing);
    expect(find.text('Frieren'), findsOneWidget);
  });

  testWidgets('凭据失效时给的是 Sign out 而不是 Retry', (WidgetTester tester) async {
    await pumpShelf(
      tester,
      FakeLibraryRepository(
        series: demoShelf(),
        seriesFailure: const AuthFailure(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('空书架显示空态而不是错误', (WidgetTester tester) async {
    await pumpShelf(tester, FakeLibraryRepository(series: const <Series>[]));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-empty')), findsOneWidget);
    expect(find.text('No series yet'), findsOneWidget);
    expect(find.byKey(const Key('shelf-error')), findsNothing);
  });

  testWidgets('搜索：输入后（防抖结束）只显示匹配项', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf());
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('shelf-search-field')), 'vaga');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.seriesCalls.last.query, 'vaga');
    expect(find.text('Vagabond'), findsOneWidget);
    expect(find.text('Frieren'), findsNothing);
  });

  testWidgets('库筛选：多个库时出现筛选条，点选按库过滤', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-filter')), findsOneWidget);
    await tester.tap(find.text('Manga'));
    await tester.pumpAndSettle();

    expect(repository.seriesCalls.last.libraryId, 'l2');
    expect(find.text('Sunny'), findsOneWidget);
    expect(find.text('Frieren'), findsNothing);
  });

  testWidgets('下拉刷新：拖动后重新请求第一页', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf());
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();
    final before = repository.seriesCalls.length;

    // 书架关掉了 Android 的拉伸过度滚动（液态玻璃着色器会被 Transform 打黑），
    // 但下拉刷新仍然必须靠 Overscroll 通知触发——这条钉住它没被一起关掉。
    await tester.fling(
      find.byKey(const Key('shelf-scroll')),
      const Offset(0, 320),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.seriesCalls.length, greaterThan(before));
    expect(repository.seriesCalls.last.page, 0);
  });

  testWidgets('滚到底部自动追加下一页', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: manySeries(45));
    await pumpShelf(tester, repository);
    await tester.pumpAndSettle();
    expect(repository.seriesCalls, hasLength(1));

    await tester.drag(
      find.byKey(const Key('shelf-scroll')),
      const Offset(0, -4000),
    );
    await pumpFrames(tester);

    expect(repository.seriesCalls, hasLength(2));
    expect(repository.seriesCalls.last.page, 1);
  });
}
