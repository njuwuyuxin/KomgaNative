import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/reader_finished_card.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/reader_harness.dart';

/// 书末行为：完成卡片、下一本、回系列，以及"末页再翻直接进下一本"。
void main() {
  Book volume(int number) => Book(
    id: 's1-b$number',
    seriesId: 's1',
    name: 'Vol. $number',
    number: '$number',
    pagesCount: 3,
  );

  List<Override> library({int bookCount = 6}) {
    final repository = FakeLibraryRepository(series: demoShelf())
      ..bookCount = bookCount;
    return <Override>[libraryRepositoryProvider.overrideWithValue(repository)];
  }

  testWidgets('没读完不显示完成卡片', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: volume(1),
      bookId: 's1-b1',
      extraOverrides: library(),
    );

    expect(find.byType(ReaderFinishedCard), findsNothing);
  });

  testWidgets('读到最后一页：完成卡片出现，并给出下一本的封面、书名与卷号', (WidgetTester tester) async {
    Book? opened;
    await pumpReader(
      tester,
      book: volume(1),
      bookId: 's1-b1',
      onOpenNext: (Book next) => opened = next,
      extraOverrides: library(),
    );

    await tapRight(tester);
    await tapRight(tester);

    expect(find.byKey(const Key('reader-finished')), findsOneWidget);
    expect(find.byType(ReaderFinishedCard), findsOneWidget);
    // 卡片比原来的条多两项：下一本的书名和卷号。
    expect(find.text('Vol. 2'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-next-book')));
    await tester.pumpAndSettle();
    expect(opened?.id, 's1-b2');
  });

  testWidgets('最后一本：只有完成提示，没有"下一本"', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: volume(6),
      bookId: 's1-b6',
      extraOverrides: library(bookCount: 6),
    );

    await tapRight(tester);
    await tapRight(tester);

    expect(find.byKey(const Key('reader-finished')), findsOneWidget);
    expect(find.byKey(const Key('reader-next-book')), findsNothing);
    expect(find.text('Finished'), findsOneWidget);
  });

  testWidgets('书列表拿不到时只是不显示下一本，不报错', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: volume(1),
      bookId: 's1-b1',
      extraOverrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(
          FakeLibraryRepository(series: demoShelf())
            ..booksFailure = const NetworkFailure()
            ..bookCount = 0,
        ),
      ],
    );

    await tapRight(tester);
    await tapRight(tester);

    expect(find.byKey(const Key('reader-finished')), findsOneWidget);
    expect(find.byKey(const Key('reader-next-book')), findsNothing);
  });

  testWidgets('读完最后一屏还继续往前翻：直接进下一本', (WidgetTester tester) async {
    Book? opened;
    await pumpReader(
      tester,
      book: volume(1),
      bookId: 's1-b1',
      onOpenNext: (Book next) => opened = next,
      extraOverrides: library(),
    );

    // 第 3 页（书尾）之后没有可翻的屏了，`turn` 会把请求原样抛给 `onTurn`。
    await tapRight(tester);
    await tapRight(tester);
    expect(find.byKey(const Key('reader-finished')), findsOneWidget);
    expect(opened, isNull);

    await tapRight(tester);
    expect(opened?.id, 's1-b2');
  });

  testWidgets('翻到书尾往回翻不会误开下一本', (WidgetTester tester) async {
    Book? opened;
    await pumpReader(
      tester,
      book: volume(1),
      bookId: 's1-b1',
      onOpenNext: (Book next) => opened = next,
      extraOverrides: library(),
    );

    await tapRight(tester);
    await tapRight(tester);
    await tapLeft(tester);

    expect(opened, isNull);
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
