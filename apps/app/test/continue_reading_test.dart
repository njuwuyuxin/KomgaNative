import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/continue_reading_row.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// "继续阅读"横排：出现条件、进度文案、点击时带上系列方向。
void main() {
  Future<List<({Book book, ReadingDirection direction})>> pumpRow(
    WidgetTester tester, {
    required FakeLibraryRepository repository,
  }) async {
    final opened = <({Book book, ReadingDirection direction})>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ContinueReadingRow(
              onOpen: (Book book, ReadingDirection direction) =>
                  opened.add((book: book, direction: direction)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('有 ondeck 数据时显示横排与进度', (WidgetTester tester) async {
    await pumpRow(
      tester,
      repository: FakeLibraryRepository(
        series: demoShelf(),
        ondeck: demoOndeck(),
      ),
    );

    expect(find.byKey(const Key('continue-reading')), findsOneWidget);
    expect(find.byKey(const Key('continue-s1-b1')), findsOneWidget);
    expect(find.text('p. 5 / 12'), findsOneWidget);
  });

  testWidgets('没有数据/失败时整行不占位', (WidgetTester tester) async {
    await pumpRow(
      tester,
      repository: FakeLibraryRepository(series: demoShelf()),
    );
    expect(find.byKey(const Key('continue-reading')), findsNothing);

    await pumpRow(
      tester,
      repository: FakeLibraryRepository(
        series: demoShelf(),
        ondeck: demoOndeck(),
      )..ondeckFailure = const NetworkFailure(),
    );
    expect(find.byKey(const Key('continue-reading')), findsNothing);
  });

  testWidgets('点击时把系列阅读方向一起带出去', (WidgetTester tester) async {
    final book = Book(
      id: 's4-b1',
      seriesId: 's4',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 6,
      readProgress: ReadProgress(
        page: 2,
        completed: false,
        lastModified: DateTime.utc(2026, 11, 1),
      ),
    );
    final opened = await pumpRow(
      tester,
      repository: FakeLibraryRepository(
        series: demoShelf(),
        ondeck: <Book>[book],
      ),
    );

    await tester.tap(find.byKey(const Key('continue-s4-b1')));
    await tester.pumpAndSettle();

    expect(opened.single.book.id, 's4-b1');
    // demoShelf 里 s4（Akira）是右到左。
    expect(opened.single.direction, ReadingDirection.rightToLeft);
  });
}
