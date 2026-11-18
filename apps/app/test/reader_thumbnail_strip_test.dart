import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P1-2：底栏上方的横向缩略图滑条。
void main() {
  ListView strip(WidgetTester tester) =>
      tester.widget<ListView>(find.byKey(const Key('reader-thumb-strip')));

  BoxBorder borderOf(WidgetTester tester, int page) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(Key('reader-thumb-$page')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).border!;
  }

  testWidgets('chrome 打开时滑条可见，点缩略图跳到那一页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 12),
      book: demoReaderBook(),
    );

    expect(find.byKey(const Key('reader-thumb-strip')), findsOneWidget);
    expect(find.byKey(const Key('reader-thumb-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-thumb-5')));
    await tester.pumpAndSettle();

    expect(find.text('5 / 12'), findsOneWidget);
  });

  testWidgets('当前页高亮，翻页后高亮跟着走', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    final current = borderOf(tester, 1) as Border;
    expect(current.top.width, AppSizes.hairline * 2);

    await tapRight(tester);
    expect((borderOf(tester, 2) as Border).top.width, AppSizes.hairline * 2);
    expect((borderOf(tester, 1) as Border).top.width, AppSizes.hairline);
  });

  testWidgets('只请求可见范围内的页（不是整本）', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 60);
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    expect(repository.pageRequests, contains(1));
    expect(
      repository.pageRequests,
      isNot(contains(60)),
      reason: '滑条是懒构建的，最远那页不该被顺手拖下来',
    );
  });

  testWidgets('读到大后面时自动居中：滑条滚到当前页附近', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 40);
    final book = Book(
      id: 'b1',
      seriesId: 's1',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 40,
      readProgress: ReadProgress(
        page: 30,
        completed: false,
        lastModified: DateTime.utc(2026, 1, 1),
      ),
    );
    await pumpReader(tester, repository: repository, book: book);

    expect(find.text('30 / 40'), findsOneWidget);
    final controller = strip(tester).controller!;
    expect(
      controller.offset,
      greaterThan(0),
      reason: '第 30 页要靠滚动才能进视口，说明确实居中了',
    );
  });

  testWidgets('RTL 的书：滑条方向镜像（第一页在最右）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );

    expect(strip(tester).reverse, isTrue);
    final first = tester.getRect(find.byKey(const Key('reader-thumb-1')));
    final last = tester.getRect(find.byKey(const Key('reader-thumb-3')));
    expect(first.center.dx, greaterThan(last.center.dx));
  });

  testWidgets('双页模式按屏分组：一条缩略图代表一跨页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 6),
      book: demoReaderBook(),
    );
    await pickMode(tester, ReaderModeChoice.double);

    // 6 页 → 封面单独一屏 + 2 个跨页 + …（末页奇数时单独一屏）：
    // 关键是滑条里不再是一页一条 —— 第 2 条对应 2–3。
    expect(find.byKey(const Key('reader-thumb-2')), findsOneWidget);
    expect(screenCountOf(tester), lessThan(6));
  });

  testWidgets('墨水屏同样有滑条（保留，只是不做惯性动画）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), forceEink: true);

    expect(find.byKey(const Key('reader-thumb-strip')), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const Key('reader-thumb-1')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    // 墨水屏用纸色底 + 墨色描边（不是深色半透明）。
    expect(
      (box.decoration as BoxDecoration).color,
      ReaderPalette.eink.background,
    );
  });

  testWidgets('拖动滑条时每经过一屏振一次', (WidgetTester tester) async {
    final haptics = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add('${call.arguments}');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 40),
      book: demoReaderBook(),
    );
    haptics.clear();

    await tester.drag(
      find.byKey(const Key('reader-thumb-strip')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();

    expect(haptics, isNotEmpty, reason: '拖动经过新的一屏应该给 selection 触感');
    expect(
      haptics.every((String h) => h == 'HapticFeedbackType.selectionClick'),
      isTrue,
    );
  });

  testWidgets('隐藏 chrome 后滑条一起隐藏', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    expect(find.byKey(const Key('reader-thumb-strip')), findsOneWidget);

    await tapMiddle(tester);

    expect(find.byKey(const Key('reader-thumb-strip')), findsNothing);
  });
}

/// 滑条里一共几条（= 屏数），从 `ListView.itemCount` 读。
int screenCountOf(WidgetTester tester) {
  final list = tester.widget<ListView>(
    find.byKey(const Key('reader-thumb-strip')),
  );
  return list.semanticChildCount ?? 0;
}
