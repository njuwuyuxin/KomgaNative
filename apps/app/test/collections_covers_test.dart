import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/collections_screen.dart';
import 'package:komga_native/src/widgets/collection_covers.dart';
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

  testWidgets('没有封面时用首字母色块（不崩）', (WidgetTester tester) async {
    await pumpCollections(tester);
    // 假仓库不返回封面字节：两张卡都应该退回首字母块。
    expect(find.text('R'), findsWidgets);
    expect(find.text('E'), findsOneWidget);
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
