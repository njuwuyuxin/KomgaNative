import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/book_selection_provider.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// SER-02：系列内书列表的多选、批量标记、以及"标记之前所有"。
void main() {
  late FakeLibraryRepository repository;

  Future<ProviderContainer> pumpSeries(WidgetTester tester) async {
    repository = FakeLibraryRepository(series: demoShelf().take(1).toList())
      ..bookCount = 4;
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
          home: SeriesDetailScreen(seriesId: demoShelf().first.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SeriesDetailScreen)),
    );
  }

  testWidgets('进入多选后点书行是勾选，不是打开阅读器', (WidgetTester tester) async {
    final container = await pumpSeries(tester);

    await tester.tap(find.byKey(const Key('series-books-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-selection-bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-s1-b1')));
    await tester.pumpAndSettle();
    expect(container.read(bookSelectionProvider).ids, <String>{'s1-b1'});

    await tester.tap(find.byKey(const Key('book-s1-b2')));
    await tester.pumpAndSettle();
    expect(container.read(bookSelectionProvider).ids.length, 2);
  });

  testWidgets('全选 + 批量标记已读：逐本调用并退出多选', (WidgetTester tester) async {
    final container = await pumpSeries(tester);

    await tester.tap(find.byKey(const Key('series-books-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-selection-all')));
    await tester.pumpAndSettle();
    expect(container.read(bookSelectionProvider).ids.length, 4);

    await tester.tap(find.byKey(const Key('shelf-batch-read')));
    await tester.pumpAndSettle();

    expect(repository.bookReadCalls.length, 4);
    expect(repository.bookReadCalls.every((c) => c.read), isTrue);
    expect(container.read(bookSelectionProvider).ids, isEmpty);
    expect(find.byKey(const Key('shelf-selection-bar')), findsNothing);
    expect(find.text('Marked 4 books as read'), findsOneWidget);
  });

  testWidgets('长按书行："标记之前所有为已读"只动前面那几本', (WidgetTester tester) async {
    await pumpSeries(tester);

    // 长按第 3 本 → 之前两本（b1、b2）。
    await tester.longPress(find.byKey(const Key('book-s1-b3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark previous as read'));
    await tester.pumpAndSettle();

    expect(repository.bookReadCalls.map((c) => c.bookId).toSet(), <String>{
      's1-b1',
      's1-b2',
    });
    expect(repository.bookReadCalls.every((c) => c.read), isTrue);
  });

  testWidgets('第一本书没有"之前所有"', (WidgetTester tester) async {
    await pumpSeries(tester);

    await tester.longPress(find.byKey(const Key('book-s1-b1')));
    await tester.pumpAndSettle();

    expect(find.text('Mark previous as read'), findsNothing);
    expect(find.byKey(const Key('book-s1-b1')), findsOneWidget);
    expect(find.text('Mark previous as read'), findsNothing);
  });
}
