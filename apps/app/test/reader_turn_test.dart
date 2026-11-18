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
