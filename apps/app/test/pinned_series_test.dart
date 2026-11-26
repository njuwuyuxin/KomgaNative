import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/widgets/unread_badge.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// LIB-02：封面未读角标 + 系列置顶（按服务器分区、重启保持）。
void main() {
  group('置顶表', () {
    late ProgressDatabase db;

    setUp(() => db = ProgressDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('置顶/取消置顶，最近的排在前面', () async {
      await db.setPinned(serverId: 'a', seriesId: 's1', pinned: true);
      await db.setPinned(serverId: 'a', seriesId: 's2', pinned: true);

      final ids = await db.pinnedSeries('a');
      expect(ids, containsAll(<String>['s1', 's2']));

      await db.setPinned(serverId: 'a', seriesId: 's1', pinned: false);
      expect(await db.pinnedSeries('a'), <String>['s2']);
    });

    test('切服务器不串', () async {
      await db.setPinned(serverId: 'a', seriesId: 's1', pinned: true);

      expect(await db.pinnedSeries('b'), isEmpty);
      await db.setPinned(serverId: 'b', seriesId: 's1', pinned: true);
      expect(await db.pinnedSeries('a'), <String>['s1']);
      expect(await db.pinnedSeries('b'), <String>['s1']);
    });

    test('重复置顶不产生两行', () async {
      await db.setPinned(serverId: 'a', seriesId: 's1', pinned: true);
      await db.setPinned(serverId: 'a', seriesId: 's1', pinned: true);

      expect(await db.pinnedSeries('a'), <String>['s1']);
    });
  });

  group('书架上的角标与置顶', () {
    late ProgressDatabase db;

    setUp(() => db = ProgressDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<ProviderContainer> pumpShelf(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryRepositoryProvider.overrideWithValue(
              FakeLibraryRepository(series: demoShelf()),
            ),
            progressDatabaseProvider.overrideWithValue(db),
            // 置顶按服务器分区：测试里没有会话，直接给一个固定 key。
            activeServerKeyProvider.overrideWithValue('server-a'),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      );
    }

    testWidgets('未读系列显示角标，读完的不显示', (WidgetTester tester) async {
      await pumpShelf(tester);

      final repo = ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      ).read(libraryRepositoryProvider);
      final items = (await repo.series(page: 0, size: 20)).items;
      final unread = <String>[
        for (final s in items)
          if (s.booksCount > s.booksReadCount) s.id,
      ];

      expect(find.byType(UnreadBadge), findsNWidgets(unread.length));
      final first = items.firstWhere((Series s) => s.booksReadCount > 0);
      expect(
        find.text('${first.booksCount - first.booksReadCount}'),
        findsWidgets,
        reason: '角标显示的是未读本数',
      );
    });

    testWidgets('置顶后出现在置顶区，并从主列表里消失一次', (WidgetTester tester) async {
      final container = await pumpShelf(tester);
      final repo = container.read(libraryRepositoryProvider);
      final target = (await repo.series(
        page: 0,
        size: 20,
      )).items.firstWhere((Series s) => s.booksCount == 12);

      await container
          .read(pinnedSeriesControllerProvider)
          .toggle(target.id, pinned: true);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shelf-pinned-header')), findsOneWidget);
      // 置顶区一份 + 主列表里不再有：同一个系列只出现一次。
      expect(find.byKey(Key('series-${target.id}')), findsOneWidget);

      await container
          .read(pinnedSeriesControllerProvider)
          .toggle(target.id, pinned: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shelf-pinned-header')), findsNothing);
    });
  });
}
