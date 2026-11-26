import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// LIB-01：书架大标题 + 系列数 + 生效中的筛选条件（可单独清除）。
void main() {
  Future<void> pumpShelf(
    WidgetTester tester, {
    FakeLibraryRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testSourceOverrides(
          library:
              repository ??
              FakeLibraryRepository(
                series: demoShelf(),
                libraries: demoLibraries(),
              ),
        ),
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
  }

  testWidgets('没有筛选时不显示 chips', (WidgetTester tester) async {
    await pumpShelf(tester);

    expect(find.byKey(const Key('shelf-active-filters')), findsNothing);
  });

  testWidgets('排序 / 状态 / 库筛选各生成一个 chip，可单独清除', (WidgetTester tester) async {
    await pumpShelf(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    final controller = container.read(shelfProvider.notifier);

    controller.setSort(SeriesSort.titleDesc);
    controller.setReadStatus(SeriesReadStatus.unread);
    controller.selectLibrary('l2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-active-filters')), findsOneWidget);
    expect(find.byKey(const Key('shelf-chip-sort')), findsOneWidget);
    expect(find.byKey(const Key('shelf-chip-status')), findsOneWidget);
    expect(find.byKey(const Key('shelf-chip-library')), findsOneWidget);

    // 单独清除排序：另外两个条件还在。
    await tester.tap(find.byKey(const Key('shelf-chip-sort')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-chip-sort')), findsNothing);
    expect(find.byKey(const Key('shelf-chip-status')), findsOneWidget);
    expect(container.read(shelfProvider).sort, isNull);
    expect(container.read(shelfProvider).readStatus, SeriesReadStatus.unread);
  });

  testWidgets('两个以上条件时出现"清除全部"', (WidgetTester tester) async {
    await pumpShelf(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    final controller = container.read(shelfProvider.notifier);

    controller.setReadStatus(SeriesReadStatus.read);
    await tester.pumpAndSettle();
    // 只有一个条件：不显示"清除全部"（那个 chip 自己就能清）。
    expect(find.byKey(const Key('shelf-clear-filters')), findsNothing);

    controller.setSort(SeriesSort.recentlyAdded);
    await tester.pumpAndSettle();
    final clearAll = find.byKey(const Key('shelf-clear-filters'));
    await tester.ensureVisible(clearAll);
    await tester.pumpAndSettle();
    await tester.tap(clearAll);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-active-filters')), findsNothing);
    final state = container.read(shelfProvider);
    expect(state.sort, isNull);
    expect(state.readStatus, isNull);
    expect(state.libraryId, isNull);
  });
}
