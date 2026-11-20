import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P1-6 双击缩放：双击中间放大 2.5 倍、再双击还原，并且不跟"单击切 chrome"
/// 打架（左右翻页区保持立即响应）。
void main() {
  testWidgets('双击中间放大到 2.5 倍', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    final before = tester.getRect(find.byKey(const Key('reader-image-0')));

    await doubleTapMiddle(tester);

    final after = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(after.width, closeTo(before.width * 2.5, 4));
    expect(
      after.left,
      closeTo(-before.width * 0.75, 8),
      reason: '以双击点（视口中间）为中心放大，两侧各被挤出 3/4 屏',
    );
    expect(find.text('1 / 3'), findsOneWidget, reason: '双击不是翻页');
  });

  testWidgets('再双击一次还原', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    final before = tester.getRect(find.byKey(const Key('reader-image-0')));

    await doubleTapMiddle(tester);
    await doubleTapMiddle(tester);

    expect(
      tester.getRect(find.byKey(const Key('reader-image-0'))),
      before,
      reason: '还原后位置和尺寸都要回到初始',
    );
  });

  testWidgets('双击后单指拖动是平移', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await doubleTapMiddle(tester);
    final zoomed = tester.getRect(find.byKey(const Key('reader-image-0')));

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    final moved = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(moved.left, greaterThan(zoomed.left), reason: '往右拖，画面跟着右移');
    expect(moved.width, closeTo(zoomed.width, 1), reason: '拖动不该改变比例');
    expect(find.text('1 / 3'), findsOneWidget, reason: '放大时拖动不翻页');
  });

  testWidgets('单击中间仍然切换 chrome（只是等了一个双击窗口）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    expect(find.byTooltip('Close'), findsOneWidget);

    await tapMiddle(tester);
    expect(find.byTooltip('Close'), findsNothing);

    // 切换 chrome 不会改变缩放。
    final page = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(page.width, lessThan(420));
  });

  testWidgets('左右翻页区双击不会变成缩放（保持立即翻页）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final right = Offset(rect.right - rect.width * 0.05, rect.center.dy);
    // 两次快速点右侧：第一次就开始翻页，第二次落在动画里被忽略。
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(right);
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const Key('reader-image-1')));
    expect(page.width, lessThan(420), reason: '没有放大');
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('缩放态下点右侧不翻页（先缩回适配尺寸）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await doubleTapMiddle(tester);

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget, reason: '放大时不响应翻页点击');
  });

  testWidgets('墨水屏 / 减少动态效果：双击直接到位，不跑弹簧', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), forceEink: true);
    final before = tester.getRect(find.byKey(const Key('reader-image-0')));

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(rect.center);
    // 只推进一帧：墨水屏不该有过渡帧。
    await tester.pump();

    final after = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(after.width, closeTo(before.width * 2.5, 4));
  });

  testWidgets('设置里选的适配方式会影响双击放大后的位置', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(fit: ReaderFitChoice.cover),
      ),
    );
    final cover = tester.getRect(find.byKey(const Key('reader-image-0')));

    await doubleTapMiddle(tester);

    final zoomed = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(zoomed.width, closeTo(cover.width * 2.5, 8));
  });
}
