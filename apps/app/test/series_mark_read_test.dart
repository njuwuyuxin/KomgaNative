import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// 系列详情：标记全部已读 / 未读。
void main() {
  Future<FakeLibraryRepository> pumpSeries(
    WidgetTester tester, {
    ShelfFailure? failure,
  }) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    repository.seriesReadFailure = failure;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SeriesDetailScreen(seriesId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('series-mark-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('标记全部已读：调用仓库并刷新详情与书列表', (WidgetTester tester) async {
    final repository = await pumpSeries(tester);
    final seriesCallsBefore = repository.seriesByIdCalls;
    final bookCallsBefore = repository.booksCalls;

    await choose(tester, 'Mark all read');

    expect(repository.seriesReadCalls.single, (seriesId: 's1', read: true));
    expect(repository.seriesByIdCalls, greaterThan(seriesCallsBefore));
    expect(repository.booksCalls, greaterThan(bookCallsBefore));
  });

  testWidgets('标记全部未读：read=false', (WidgetTester tester) async {
    final repository = await pumpSeries(tester);

    await choose(tester, 'Mark all unread');

    expect(repository.seriesReadCalls.single, (seriesId: 's1', read: false));
  });

  testWidgets('失败只弹 SnackBar，详情页不会变成错误页', (WidgetTester tester) async {
    final repository = await pumpSeries(
      tester,
      failure: const NetworkFailure(),
    );

    await choose(tester, 'Mark all read');

    expect(repository.seriesReadCalls, hasLength(1));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(const Key('series-error')), findsNothing);
    expect(find.text('Frieren'), findsWidgets);
  });

  testWidgets('标记已读后联动刷新已挂载的书架与最近添加（ARC-10）', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SeriesDetailScreen(seriesId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SeriesDetailScreen)),
    );
    // 先挂载书架状态机与最近系列缓存。
    container.read(shelfProvider);
    await container.read(recentSeriesProvider.future);
    await tester.pumpAndSettle();
    final shelfCallsBefore = repository.seriesCalls.length;

    await choose(tester, 'Mark all read');

    expect(
      repository.seriesCalls.length,
      greaterThan(shelfCallsBefore),
      reason: '书架应由 SeriesReadController 自动触发 refreshInPlace',
    );
  });
}
