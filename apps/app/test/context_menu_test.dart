import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// UI-P2-5：长按上下文菜单 + 单本书标记已读/未读。
void main() {
  Future<FakeLibraryRepository> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    FakeLibraryRepository? repository,
  }) async {
    final library = repository ?? FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testSourceOverrides(library: library),
        child: MaterialApp(
          key: UniqueKey(),
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return library;
  }

  group('系列菜单', () {
    testWidgets('长按系列卡片弹出菜单：全部已读 / 全部未读 / 查看详情', (WidgetTester tester) async {
      await pumpScreen(tester, const LibraryScreen());

      await tester.longPress(find.byKey(const Key('series-s1')));
      await tester.pumpAndSettle();

      expect(find.text('Mark all read'), findsOneWidget);
      expect(find.text('Mark all unread'), findsOneWidget);
      // ignore: avoid_print
      print(
        'TEXTS: '
        '${tester.widgetList<Text>(find.byType(Text, skipOffstage: false)).map((Text t) => t.data).where((String? d) => d != null).toList()}',
      );
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('View details', skipOffstage: false), findsOneWidget);
    });

    testWidgets('选"标记全部已读"→ 调仓库', (WidgetTester tester) async {
      final repository = await pumpScreen(tester, const LibraryScreen());

      await tester.longPress(find.byKey(const Key('series-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(repository.seriesReadCalls, <({String seriesId, bool read})>[
        (seriesId: 's1', read: true),
      ]);
    });

    testWidgets('选"标记全部未读"→ 调仓库 read=false', (WidgetTester tester) async {
      final repository = await pumpScreen(tester, const LibraryScreen());

      await tester.longPress(find.byKey(const Key('series-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all unread'));
      await tester.pumpAndSettle();

      expect(repository.seriesReadCalls.single.read, isFalse);
    });

    testWidgets('断网时选"标记全部已读"：不抛未捕获异常且弹出错误 SnackBar', (
      WidgetTester tester,
    ) async {
      final repository = FakeLibraryRepository(series: demoShelf())
        ..seriesReadFailure = const NetworkFailure();
      await pumpScreen(tester, const LibraryScreen(), repository: repository);

      await tester.longPress(find.byKey(const Key('series-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cannot reach the server'), findsOneWidget);
    });

    testWidgets('墨水屏同样有菜单（普通弹出，不做缩放）', (WidgetTester tester) async {
      final library = FakeLibraryRepository(series: demoShelf());
      tester.view.physicalSize = const Size(758 * 2, 1024 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: testSourceOverrides(library: library),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.eink(),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('series-s1')));
      await tester.pumpAndSettle();
      expect(find.text('Mark all read'), findsOneWidget);
    });
  });

  group('书的菜单', () {
    testWidgets('长按一本书 → 标记已读调仓库（带页数）', (WidgetTester tester) async {
      final repository = await pumpScreen(
        tester,
        const SeriesDetailScreen(seriesId: 's1'),
      );

      await tester.longPress(find.byKey(const Key('book-s1-b3')));
      await tester.pumpAndSettle();
      expect(find.text('Mark read'), findsOneWidget);
      expect(find.text('Mark unread'), findsOneWidget);

      await tester.tap(find.text('Mark read'));
      await tester.pumpAndSettle();

      final call = repository.bookReadCalls.single;
      expect(call.bookId, 's1-b3');
      expect(call.read, isTrue);
      expect(
        call.pagesCount,
        21,
        reason: 'FakeLibraryRepository 里第 3 本是 18+3 页',
      );
    });

    testWidgets('长按一本书 → 标记未读调仓库', (WidgetTester tester) async {
      final repository = await pumpScreen(
        tester,
        const SeriesDetailScreen(seriesId: 's1'),
      );

      await tester.longPress(find.byKey(const Key('book-s1-b3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark unread'));
      await tester.pumpAndSettle();

      expect(repository.bookReadCalls.single.read, isFalse);
    });
  });
}
