import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/shelf_selection_provider.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// LIB-03：书架多选与批量操作。
///
/// 入口是顶部工具条的"选择"按钮，**不是长按**：长按在书架上是系列菜单
/// （标记已读/置顶/详情），一个手势不能同时做两件事。
void main() {
  late FakeLibraryRepository repository;

  Future<ProviderContainer> pumpShelf(WidgetTester tester) async {
    repository = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
  }

  /// 点"选择"进入多选态。
  Future<void> enterSelection(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('shelf-select-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('进入多选后点卡片是勾选，不是打开系列', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    final ids = (await repository.series(
      page: 0,
      size: 20,
    )).items.map((s) => s.id).toList();

    await enterSelection(tester);
    expect(find.byKey(const Key('shelf-selection-bar')), findsOneWidget);

    await tester.tap(find.byKey(Key('series-${ids[0]}')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids, <String>{ids[0]});

    // 点第二张卡片：加选，而不是进系列页。
    await tester.tap(find.byKey(Key('series-${ids[1]}')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids.length, 2);
    expect(find.byKey(const Key('shelf-search-field')), findsNothing);
  });

  testWidgets('全选与取消', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    final total = (await repository.series(page: 0, size: 20)).items.length;

    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('shelf-selection-all')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids.length, total);

    await tester.tap(find.byKey(const Key('shelf-selection-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-selection-bar')), findsNothing);
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
    expect(container.read(shelfSelectionProvider).active, isFalse);
  });

  testWidgets('批量标记已读：逐个调用并退出多选', (WidgetTester tester) async {
    final container = await pumpShelf(tester);

    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-batch-read')));
    await tester.pumpAndSettle();

    expect(repository.seriesReadCalls.length, 2);
    expect(repository.seriesReadCalls.every((c) => c.read), isTrue);
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
    expect(find.byKey(const Key('shelf-selection-bar')), findsNothing);
  });

  testWidgets('失败项不影响其余项', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();
    // 让每一次标记都失败。
    repository.seriesReadFailure = const UnexpectedFailure('boom');

    await tester.tap(find.byKey(const Key('shelf-batch-read')));
    await tester.pumpAndSettle();

    expect(repository.seriesReadCalls.length, 2, reason: '一个失败不影响下一个');
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
  });
}
