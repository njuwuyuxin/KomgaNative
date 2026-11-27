import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/missing_source_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/screens/series_detail_args.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:yomu/src/widgets/curation_detail_rows.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// P1-2：/series/:id 跳转显式带 sourceKey、置顶按 series.sourceKey 分区、
/// 服务器登出后已打开的系列详情页绝不退回查询本机库。
void main() {
  const remoteKey = 'https://komga.p12.test';

  test('PinnedSeries 按系列自身 sourceKey 分区，切到本机后不串区（P1-2）', () async {
    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final remoteSeries = const Series(
      id: 'komga-s1',
      libraryId: 'lib-1',
      title: 'Cloud Series',
    ).withSource(remoteKey);
    final localRepo = FakeLibraryRepository();
    final remoteRepo = FakeLibraryRepository(series: <Series>[remoteSeries]);

    final container = ProviderContainer(
      overrides: [
        progressDatabaseProvider.overrideWithValue(db),
        activeSourceProvider.overrideWith(
          () => FixedActiveSourceController(const LocalContentSource()),
        ),
        libraryRepositoryForSourceProvider.overrideWith((
          Ref ref,
          String sourceKey,
        ) {
          if (sourceKey == remoteKey) return remoteRepo;
          if (isLocalSourceKey(sourceKey)) return localRepo;
          return MissingSourceRepository(sourceKey);
        }),
      ],
    );
    addTearDown(container.dispose);

    // 激活源是本机，但对云端系列置顶时显式传 remoteKey。
    await container
        .read(pinnedSeriesControllerProvider)
        .toggle('komga-s1', pinned: true, sourceKey: remoteKey);

    expect(
      await container.read(pinnedSeriesIdsForSourceProvider(remoteKey).future),
      <String>['komga-s1'],
    );
    expect(
      await container.read(
        pinnedSeriesIdsForSourceProvider(kLocalSourceKey).future,
      ),
      isEmpty,
    );

    final remotePinned = await container.read(
      pinnedSeriesForSourceProvider(remoteKey).future,
    );
    expect(remotePinned.map((Series s) => s.id), <String>['komga-s1']);
  });

  testWidgets('收藏集系列列表点击云端系列携带 ?source= 与 SeriesDetailArgs.sourceKey（P1-2）', (
    WidgetTester tester,
  ) async {
    String? pushedUri;
    SeriesDetailArgs? pushedArgs;
    final cloudSeries = const Series(
      id: 'remote-series-42',
      libraryId: 'lib-1',
      title: 'Dandadan',
      booksCount: 10,
    ).withSource(remoteKey);

    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                CollectionSeriesSliver(
                  collectionId: 'col-1',
                  async: AsyncValue.data(
                    PageResult<Series>(
                      items: <Series>[cloudSeries],
                      page: 0,
                      size: 20,
                      totalElements: 1,
                    ),
                  ),
                  hiddenIds: const <String>{},
                  onRetry: () {},
                  onLoadMore: () {},
                  onRemove: (_, {bool fromSwipe = false}) async => false,
                  onLongPressSeries: (_, _, _) async {},
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/series/:seriesId',
          builder: (BuildContext context, GoRouterState state) {
            pushedUri = state.uri.toString();
            pushedArgs = state.extra as SeriesDetailArgs?;
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seriesCoverProvider.overrideWith(
            (Ref ref, CoverQuery key) async => null,
          ),
          pinnedSeriesIdsForSourceProvider.overrideWith(
            (Ref ref, String sourceKey) async => const <String>[],
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dandadan'));
    await tester.pumpAndSettle();

    expect(
      pushedUri,
      '/series/remote-series-42?source=${Uri.encodeComponent(remoteKey)}',
    );
    expect(pushedArgs?.sourceKey, remoteKey);
  });

  testWidgets('Komga 系列详情页开着时切回本机源，不会用 Komga id 去查本机库（P1-2）', (
    WidgetTester tester,
  ) async {
    var localSeriesByIdCalls = 0;
    final localRepo = _CountingLibraryRepo(
      onSeriesById: () => localSeriesByIdCalls++,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSourceProvider.overrideWith(
            () => FixedActiveSourceController(const LocalContentSource()),
          ),
          libraryRepositoryForSourceProvider.overrideWith((
            Ref ref,
            String sourceKey,
          ) {
            if (isLocalSourceKey(sourceKey)) return localRepo;
            return MissingSourceRepository(sourceKey);
          }),
          collectionsRepositoryForSourceProvider.overrideWith((
            Ref ref,
            String sourceKey,
          ) {
            if (isLocalSourceKey(sourceKey)) return localRepo;
            return MissingSourceRepository(sourceKey);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SeriesDetailScreen(
            seriesId: 'komga-deleted-series',
            sourceKey: remoteKey,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 服务器已登出/删除且激活源已切回本机：但因为携带了显式 remoteKey，绝不查询本机库！
    expect(localSeriesByIdCalls, 0);
  });
}

class _CountingLibraryRepo extends FakeLibraryRepository {
  _CountingLibraryRepo({required this.onSeriesById});

  final VoidCallback onSeriesById;

  @override
  Future<Series?> seriesById(String id) async {
    onSeriesById();
    return super.seriesById(id);
  }
}
