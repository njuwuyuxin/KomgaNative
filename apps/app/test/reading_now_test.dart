import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reading_now_screen.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P2-6「正在读」首页：继续阅读卡片、最近添加、按库分组。
void main() {
  Future<FakeLibraryRepository> pumpPage(
    WidgetTester tester, {
    FakeLibraryRepository? repository,
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
    await tester.pumpAndSettle();
    return library;
  }

  testWidgets('大号继续阅读卡片显示 ondeck 第一本与进度', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('reading-now-continue')), findsOneWidget);
    expect(find.text('Vol. 1'), findsOneWidget);
    // demoOndeck 第一本读到第 5 页，共 12 页。
    expect(find.text('p. 5 / 12'), findsOneWidget);
    expect(find.text('Continue reading'), findsOneWidget);
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

  testWidgets('ondeck 失败也不炸整页（只是没有继续阅读卡）', (WidgetTester tester) async {
    await pumpPage(
      tester,
      repository: FakeLibraryRepository(
        series: demoShelf(),
        libraries: demoLibraries(),
        ondeckFailure: const NetworkFailure(),
      ),
    );

    expect(find.byKey(const Key('reading-now-empty')), findsOneWidget);
    expect(find.byType(SeriesShelfTile), findsWidgets, reason: '货架照常');
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
}
