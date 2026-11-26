import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/fakes.dart';
import 'support/reader_harness.dart';

/// 阅读设置面板：模式持久化、适配、方向、背景、亮度、常亮、跳页。
void main() {
  testWidgets('面板列出七组设置', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await openSettings(tester);

    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('READING MODE'), findsOneWidget);
    expect(find.text('PAGE FIT'), findsOneWidget);
    expect(find.text('READING DIRECTION'), findsOneWidget);
    expect(find.text('BACKGROUND'), findsOneWidget);
    expect(find.text('BRIGHTNESS'), findsOneWidget);
    expect(find.text('Keep screen awake'), findsOneWidget);
    expect(find.text('GO TO PAGE'), findsOneWidget);
    // 四个模式选项都在（含"跟随书"）。
    for (final label in <String>[
      'Follow the book',
      'Single page',
      'Double page',
      'Vertical scroll',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // 适配方式四档、方向三档、背景三档。
    expect(find.text('Fit screen'), findsOneWidget);
    expect(find.text('Fill screen'), findsOneWidget);
    expect(find.text('Fit width'), findsOneWidget);
    expect(find.text('Fit height'), findsOneWidget);
    expect(find.text('Left to right'), findsOneWidget);
    expect(find.text('Right to left'), findsOneWidget);
    expect(find.text('Match the page'), findsOneWidget);
  });

  group('模式', () {
    testWidgets('选双页 → 立刻生效，并落盘', (WidgetTester tester) async {
      final store = await pumpReader(tester, book: demoReaderBook());
      await pickMode(tester, ReaderModeChoice.double);

      expect(find.text('1 / 3'), findsOneWidget);
      await tapRight(tester);
      expect(find.text('2–3 / 3'), findsOneWidget);
      expect(
        store.prefs!.global.mode,
        ReaderModeChoice.double,
        reason: '设置要记住',
      );
    });

    testWidgets('已保存的模式在下次打开时生效', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(
          global: ReaderConfig(mode: ReaderModeChoice.double),
        ),
      );

      expect(find.text('1 / 3'), findsOneWidget);
      await tapRight(tester);
      expect(find.text('2–3 / 3'), findsOneWidget);
    });

    testWidgets('显式选单页会覆盖条漫方向', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.webtoon,
        initialPrefs: const ReaderPrefs(
          global: ReaderConfig(mode: ReaderModeChoice.single),
        ),
      );

      expect(find.byKey(const Key('reader-vertical-list')), findsNothing);
      expect(find.text('1 / 3'), findsOneWidget);
    });
  });

  group('亮度', () {
    testWidgets('默认不遮罩；调暗后盖上遮罩且不吃点击', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      expect(find.byKey(const Key('reader-dimmer')), findsNothing);

      await openSettings(tester);
      final slider = find.byKey(const Key('reader-brightness-slider'));
      await revealInSheet(tester, slider);
      await tester.drag(slider, const Offset(-400, 0));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      final dimmer = tester.widget<ColoredBox>(
        find.byKey(const Key('reader-dimmer')),
      );
      // 拖到最左 = 亮度下限 0.2 → 遮罩 0.8。
      expect(dimmer.color.a, closeTo(0.8, 0.02));
      // 遮罩是 IgnorePointer，翻页仍然有效。
      await tapRight(tester);
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('调回最亮后遮罩消失', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(global: ReaderConfig(brightness: 0.4)),
      );
      expect(find.byKey(const Key('reader-dimmer')), findsOneWidget);

      await openSettings(tester);
      final slider = find.byKey(const Key('reader-brightness-slider'));
      await revealInSheet(tester, slider);
      await tester.drag(slider, const Offset(400, 0));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.byKey(const Key('reader-dimmer')), findsNothing);
    });
  });

  group('常亮', () {
    testWidgets('打开开关 → 通知平台；退出阅读器 → 放开', (WidgetTester tester) async {
      final wakeLock = FakeWakeLock();
      await pumpReader(tester, book: demoReaderBook(), wakeLock: wakeLock);
      expect(wakeLock.enabled, isFalse, reason: '默认不常亮');

      await openSettings(tester);
      final toggle = find.byKey(const Key('reader-keep-awake'));
      await revealInSheet(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(wakeLock.enabled, isTrue);

      // 离开阅读器（整棵树换掉）必须放开，否则屏幕永远不睡。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(wakeLock.enabled, isFalse);
    });

    testWidgets('偏好里已开启常亮 → 进阅读器立即生效', (WidgetTester tester) async {
      final wakeLock = FakeWakeLock();
      await pumpReader(
        tester,
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(global: ReaderConfig(keepAwake: true)),
        wakeLock: wakeLock,
      );

      expect(wakeLock.calls, contains(true));
    });
  });

  group('跳页', () {
    testWidgets('单页：拖到最后 → 跳到末页并写进度', (WidgetTester tester) async {
      final repository = FakeReaderRepository();
      await pumpReader(tester, repository: repository, book: demoReaderBook());

      await openSettings(tester);
      final slider = find.byKey(const Key('reader-jump-slider'));
      await revealInSheet(tester, slider);
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.text('3 / 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(repository.saved.last, (page: 3, completed: true));
    });

    testWidgets('双页：跳到中间页 → 落在包含它的跨页', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(
          global: ReaderConfig(mode: ReaderModeChoice.double),
        ),
      );

      await openSettings(tester);
      final slider = find.byKey(const Key('reader-jump-slider'));
      await revealInSheet(tester, slider);
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.text('2–3 / 3'), findsOneWidget);
    });

    testWidgets('纵向：跳页会滚动到目标页', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.webtoon,
      );

      await openSettings(tester);
      final slider = find.byKey(const Key('reader-jump-slider'));
      await revealInSheet(tester, slider);
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('松手后滑条停在目标页，不会弹回打开时的页码', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      await openSettings(tester);

      final slider = find.byKey(const Key('reader-jump-slider'));
      await revealInSheet(tester, slider);
      expect(tester.widget<Slider>(slider).value, 1.0);

      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();

      // 页面已经跳了，滑条也得停在末页：以前 widget.page 是打开时的快照，
      // 松手后 value 回到 1，看起来像拖动失败。
      expect(tester.widget<Slider>(slider).value, 3.0);
      expect(find.text('3 / 3'), findsWidgets, reason: '面板标签与顶栏都应是第 3 页');
    });

    testWidgets('只有一页时不显示跳页滑块', (WidgetTester tester) async {
      await pumpReader(
        tester,
        repository: FakeReaderRepository(pageCount: 1),
        book: demoReaderBook(),
      );
      await openSettings(tester);

      expect(find.text('GO TO PAGE'), findsNothing);
      expect(find.byKey(const Key('reader-jump-slider')), findsNothing);
    });
  });
}
