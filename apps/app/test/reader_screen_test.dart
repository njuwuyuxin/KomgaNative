import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';

void main() {
  Future<void> pumpReader(
    WidgetTester tester,
    FakeReaderRepository repository, {
    Book? book,
    ReadingDirection direction = ReadingDirection.leftToRight,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          readerRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: ReaderScreen(bookId: 'b1', book: book, direction: direction),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点屏幕右侧三分之一（LTR 的"下一页"）。
  Future<void> tapRight(WidgetTester tester) async {
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
    await tester.pumpAndSettle();
  }

  Future<void> tapLeft(WidgetTester tester) async {
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.left + rect.width * 0.05, rect.center.dy));
    await tester.pumpAndSettle();
  }

  testWidgets('打开即显示第一页与页码', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository, book: demoReaderBook());

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(repository.pageImageCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('有进度时从上次那一页继续', (WidgetTester tester) async {
    final book = Book(
      id: 'b1',
      seriesId: 's1',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 3,
      readProgress: ReadProgress(
        page: 2,
        completed: false,
        lastModified: DateTime.utc(2026, 1, 1),
      ),
    );
    await pumpReader(tester, FakeReaderRepository(), book: book);

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('点右侧翻页，并在防抖后把进度写回服务端', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository, book: demoReaderBook());

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);

    // 防抖 600ms 内不应写；等过去之后写一次第 2 页。
    expect(repository.saved, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));
    expect(repository.saved, <({int page, bool completed})>[
      (page: 2, completed: false),
    ]);
  });

  testWidgets('翻到最后一页时 completed 置真', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository, book: demoReaderBook());

    await tapRight(tester);
    await tapRight(tester);
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(repository.saved.last, (page: 3, completed: true));
  });

  testWidgets('右到左的书：点左侧才是下一页', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository,
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );

    await tapLeft(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('点中间隐藏/显示顶栏与底栏', (WidgetTester tester) async {
    await pumpReader(tester, FakeReaderRepository(), book: demoReaderBook());
    expect(find.byTooltip('Close'), findsOneWidget);

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);

    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('页列表加载失败 → 错误页 + 重试', (WidgetTester tester) async {
    final repository = FakeReaderRepository(
      pagesFailure: const NetworkFailure(),
    );
    await pumpReader(tester, repository, book: demoReaderBook());

    expect(find.text('Cannot reach the server'), findsOneWidget);

    repository.pagesFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('单页图加载失败 → 页内提示 + 重试', (WidgetTester tester) async {
    final repository = FakeReaderRepository(
      imageFailure: const ServerFailure(),
    );
    await pumpReader(tester, repository, book: demoReaderBook());

    expect(find.text('Server error'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget, reason: '页码仍应可用');

    repository.imageFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('进度回写失败不影响继续阅读', (WidgetTester tester) async {
    final repository = FakeReaderRepository(
      saveFailure: const NetworkFailure(),
    );
    await pumpReader(tester, repository, book: demoReaderBook());

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('2 / 3'), findsOneWidget);
  });
}
