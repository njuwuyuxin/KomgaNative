import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P1-3 适配方式、UI-P1-4 手动阅读方向。
void main() {
  group('适配方式', () {
    testWidgets('默认"适应屏幕"：整页装得下，横向不溢出', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());

      final page = tester.getRect(find.byKey(const Key('reader-image-0')));
      expect(page.width, lessThanOrEqualTo(390.5));
      expect(page.height, lessThanOrEqualTo(844.5));
    });

    testWidgets('选"填满屏幕"：横向溢出，且落盘', (WidgetTester tester) async {
      final store = await pumpReader(tester, book: demoReaderBook());
      await pickOption(tester, 'reader-fit-cover');

      expect(store.prefs!.global.fit, ReaderFitChoice.cover);
      // 800×1200 的页在 390×844 里填满 → 高度铺满（844），宽度溢出到 562。
      final page = tester.getRect(find.byKey(const Key('reader-image-0')));
      expect(page.width, greaterThan(390));
      expect(page.height, closeTo(844, 1));
    });

    testWidgets('填满屏幕时横向拖动是平移，不会翻页', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      await pickOption(tester, 'reader-fit-cover');

      final before = tester.getRect(find.byKey(const Key('reader-image-0')));
      await tester.drag(
        find.byKey(const Key('reader-tap-layer')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget, reason: '拖动是平移，不是翻页');
      final after = tester.getRect(find.byKey(const Key('reader-image-0')));
      expect(after.left, lessThan(before.left), reason: '画面跟着手指往左移');
    });

    testWidgets('选"适应宽度"：超长页高度溢出（可以上下拖）', (WidgetTester tester) async {
      await pumpReader(
        tester,
        // 2:3 的页在竖屏里"适应宽度"和"适应屏幕"是同一个结果，得用超长页才看得出差别。
        repository: FakeReaderRepository(
          pageSizes: <({int width, int height})>[(width: 800, height: 4000)],
        ),
        book: demoReaderBook(),
      );
      await pickOption(tester, 'reader-fit-fitWidth');

      final page = tester.getRect(find.byKey(const Key('reader-image-0')));
      expect(page.width, closeTo(390, 1));
      expect(page.height, greaterThan(844));
    });

    testWidgets('已保存的适配方式在下次打开时生效', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(
          global: ReaderConfig(fit: ReaderFitChoice.cover),
        ),
      );

      final page = tester.getRect(find.byKey(const Key('reader-image-0')));
      expect(page.width, greaterThan(390));
    });

    testWidgets('双页模式忽略"填满"，仍按适应屏幕（不能裁掉另一页）', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(
          global: ReaderConfig(
            mode: ReaderModeChoice.double,
            fit: ReaderFitChoice.cover,
          ),
        ),
      );
      await tapRight(tester);
      expect(find.text('2–3 / 3'), findsOneWidget);

      final second = tester.getRect(find.byKey(const Key('reader-image-1')));
      expect(second.width, lessThanOrEqualTo(195.5), reason: '两页各占一半，没有被裁');
    });
  });

  group('阅读方向', () {
    testWidgets('默认跟随系列：LTR 的书点右侧翻页', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());

      await tapRight(tester);
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('手动选"从右到左"：LTR 的书也变成点左侧翻页', (WidgetTester tester) async {
      final store = await pumpReader(tester, book: demoReaderBook());
      await pickOption(tester, 'reader-direction-rightToLeft');
      expect(store.prefs!.global.direction, ReaderDirectionChoice.rightToLeft);

      await tapLeft(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      // 底栏箭头也跟着镜像：左侧是"下一页"。
      final next = tester.getCenter(
        find.byKey(const Key('reader-next-button')),
      );
      final previous = tester.getCenter(
        find.byKey(const Key('reader-previous-button')),
      );
      expect(next.dx, lessThan(previous.dx));
    });

    testWidgets('手动选"从左到右"覆盖系列的右到左', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.rightToLeft,
      );
      // 系列是 RTL，此时点左侧才是下一页。
      await tapLeft(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      await tapRight(tester);
      expect(find.text('1 / 3'), findsOneWidget);

      await pickOption(tester, 'reader-direction-leftToRight');
      await tapRight(tester);
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('方向也跟着影响缩略图滑条（RTL 时第一页在最右）', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      await pickOption(tester, 'reader-direction-rightToLeft');

      final first = tester.getRect(find.byKey(const Key('reader-thumb-1')));
      final last = tester.getRect(find.byKey(const Key('reader-thumb-3')));
      expect(first.center.dx, greaterThan(last.center.dx));
    });
  });
}
