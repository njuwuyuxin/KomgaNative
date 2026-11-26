import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:yomu/src/widgets/collection_covers.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-02：收藏集封面拼贴 + 搜索 + 排序。
void main() {
  Future<void> pumpCollections(
    WidgetTester tester, {
    FakeLibraryRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(
            repository ?? FakeLibraryRepository(series: demoShelf()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const CollectionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('收藏集行显示拼贴与系列数', (WidgetTester tester) async {
    await pumpCollections(tester);

    expect(find.byType(CollectionCovers), findsNWidgets(2));
    expect(find.text('Reading order'), findsOneWidget);
    expect(find.text('2 series'), findsOneWidget);
    expect(find.text('0 series'), findsOneWidget);
  });

  testWidgets('不足 4 个系列时拼贴空位保持透明，不用首字母色块占位', (WidgetTester tester) async {
    await pumpCollections(tester);
    // "Empty shelf" 有 0 个系列，走空收藏集首字母 'E'；
    // "Reading order" 有 2 个系列（不足 4 格），其余 2 格透明留空，不画 'R' 占位。
    expect(find.text('E'), findsOneWidget);
    expect(find.text('R'), findsNothing);
  });

  testWidgets('搜索过滤收藏集，无结果走空态', (WidgetTester tester) async {
    await pumpCollections(tester);

    await tester.enterText(
      find.byKey(const Key('collections-search')),
      'empty',
    );
    await tester.pumpAndSettle();
    expect(find.text('Empty shelf'), findsOneWidget);
    expect(find.text('Reading order'), findsNothing);

    await tester.enterText(find.byKey(const Key('collections-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('按系列数排序后第一行换成系列多的那个', (WidgetTester tester) async {
    await pumpCollections(tester);

    await tester.tap(find.byKey(const Key('collections-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collections-sort-seriesCount')));
    await tester.pumpAndSettle();

    // 收藏集只有两条：系列数降序时 "Reading order"(2) 应该在 "Empty shelf"(0) 之上。
    final first = tester.getTopLeft(find.text('Reading order')).dy;
    final second = tester.getTopLeft(find.text('Empty shelf')).dy;
    expect(first, lessThan(second));
  });
}
