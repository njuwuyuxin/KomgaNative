import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 翻页动画的行为：点击要带动画、横滑跟手翻页、拖得不够要回弹、墨水屏不做动画。
void main() {
  testWidgets('点击翻页也播动画：第一帧还没换页，动画结束才换', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
    );

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
    await tester.pump();

    // 动画进行中：页码还没变（纸正在卷）。
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('从右往左横滑（LTR 的下一页）：跟手拖过阈值就翻页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
    );

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('只滑一点点就松手：回弹，页码不变', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
    );

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 5'), findsOneWidget, reason: '没拖够阈值不该翻页');
  });

  testWidgets('RTL：从左往右滑才是下一页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(260, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('双页模式：横滑按"屏"翻页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 6),
      book: demoReaderBook(),
    );
    await pickMode(tester, ReaderModeChoice.double);

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2–3 / 6'), findsOneWidget);
  });

  testWidgets('双页模式：位图就绪后走铰接卷页，翻完按屏换页（RTL）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 6),
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );
    await pickMode(tester, ReaderModeChoice.double);
    // 封面单独一屏（[0] → [1, 2] 页数不配对，走平移），先翻到 [1, 2]。
    final layer = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(layer.left + 10, layer.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2–3 / 6'), findsOneWidget);
    // 位图在空闲帧里真解码（instantiateImageCodec），要给真实的异步时间。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    await gesture.moveBy(Offset(rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '双页也要卷页，不能退化成平移');
    expect(state.debugHinged, isTrue, reason: '双页的纸铰接在书脊上');
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('4–5 / 6'), findsOneWidget);
  });

  testWidgets('单页：底层相邻页还没加载好，也照常卷页（掀开后露出它的加载态）', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 4);
    // 第 2 页（下一屏）挂住：它只决定"纸掀开之后露出什么"，不是卷页的条件。
    repository.pageGates[2] = Completer<void>();
    await pumpReader(tester, repository: repository, book: demoReaderBook());
    // 位图在空闲帧里真解码（instantiateImageCodec），要给真实的异步时间。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(Offset(-rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '当前这一页已就绪就该卷页；等底层只会换来一次没有卷页的平移');
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);
    expect(
      find.byKey(const Key('reader-page-loading-1')),
      findsOneWidget,
      reason: '纸掀开后露出的就是下一屏"还没加载好"的老实状态',
    );

    await gesture.up();
    // 翻过去的同时它到了：交接后不该再转圈。
    repository.pageGates[2]!.complete();
    // 第一个 tick 只是让控制器起表（elapsed = 0），第二个 tick 才播完。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 4'), findsOneWidget);
  });

  testWidgets('单页：当前页自己的纸面位图没好，仍然退化成平移', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 5)..failingPages.add(1);
    await pumpReader(tester, repository: repository, book: demoReaderBook());
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(Offset(-rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isFalse, reason: '纸面没有像素，卷起来只会是一块空白');
    expect(find.byKey(const Key('reader-curl-layer')), findsNothing);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('松手后从"当前已翻进度"补完，不会跳回起点重播', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
    );
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(Offset(-rect.width * 0.7, 0));
    await tester.pump();

    expect(state.debugProgress, closeTo(0.7, 0.05));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    // 关键：松手那一帧不能跳回 0（以前是 animateTo(1) 从 controller 的旧值 0 起播）。
    expect(state.debugProgress, greaterThan(0.6), reason: '补完动画必须从当前进度接着播');

    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('墨水屏：不做动画，点击一帧就换页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      forceEink: true,
    );

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
    await tester.pump();

    expect(find.text('2 / 3'), findsOneWidget, reason: '墨水屏不该有翻页动画');
  });
}
