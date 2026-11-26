import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_fit_preview.dart';
import 'package:yomu/src/widgets/reader_settings_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// RDR-04：完整设置面板按四组分、每组可单独重置、适配有示意图、顶部有摘要。
void main() {
  testWidgets('顶部摘要显示当前组合', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(
          mode: ReaderModeChoice.double,
          fit: ReaderFitChoice.cover,
          direction: ReaderDirectionChoice.rightToLeft,
          background: ReaderBackgroundChoice.white,
        ),
      ),
    );
    await openSettings(tester);

    final summary = tester.widget<Text>(
      find.byKey(const Key('reader-settings-summary')),
    );
    expect(summary.data, contains('Double page'));
    expect(summary.data, contains('Fill screen'));
    expect(summary.data, contains('Right to left'));
    expect(summary.data, contains('White'));
  });

  testWidgets('四组都有重置；默认时置灰，改过后可用', (WidgetTester tester) async {
    final store = await pumpReader(tester, book: demoReaderBook());
    await openSettings(tester);

    for (final group in <String>['pages', 'layout', 'color', 'interaction']) {
      final finder = find.byKey(Key('reader-reset-$group'));
      expect(finder, findsOneWidget, reason: '$group 组要有重置');
      expect(
        tester.widget<TextButton>(finder).onPressed,
        isNull,
        reason: '$group 初始是默认值，重置按钮应置灰',
      );
    }

    // 改颜色组的背景 → 只有这一组的重置变可用。
    await tester.ensureVisible(
      find.byKey(const Key('reader-background-white')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-background-white')));
    await tester.pumpAndSettle();
    expect(store.prefs?.global.background, ReaderBackgroundChoice.white);

    await tester.ensureVisible(find.byKey(const Key('reader-reset-color')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('reader-reset-color')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('reader-reset-layout')))
          .onPressed,
      isNull,
      reason: '布局组没动过，不该跟着变可用',
    );
  });

  testWidgets('点"颜色"重置：背景回默认，其它组保持不变', (WidgetTester tester) async {
    final store = await pumpReader(
      tester,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(
          mode: ReaderModeChoice.double,
          background: ReaderBackgroundChoice.white,
          brightness: 0.6,
        ),
      ),
    );
    await openSettings(tester);

    await tester.ensureVisible(find.byKey(const Key('reader-reset-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-reset-color')));
    await tester.pumpAndSettle();

    expect(store.prefs?.global.background, ReaderBackgroundChoice.black);
    expect(store.prefs?.global.brightness, 1);
    expect(
      store.prefs?.global.mode,
      ReaderModeChoice.double,
      reason: '页面组不该被重置',
    );
  });

  testWidgets('适配方式是 4 个小示意图', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('reader-fit-cover')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderFitPreview), findsNWidgets(4));
    expect(
      tester
          .widget<ReaderFitPreview>(find.byType(ReaderFitPreview).first)
          .palette
          .isEink,
      isFalse,
    );
  });

  testWidgets('交互组里有翻页动画，选"淡入"会落盘（RDR-05）', (WidgetTester tester) async {
    final store = await pumpReader(tester, book: demoReaderBook());

    // 走公共 pickOption：打开面板 → 滚到该行 → 点 → 关面板。
    await pickOption(tester, 'reader-turn-fade');

    expect(store.prefs?.global.pageTurn, ReaderPageTurnChoice.fade);
  });

  testWidgets('墨水屏：示意图拿到线框调色板，且没有背景组', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), forceEink: true);
    await openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('reader-fit-cover')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ReaderFitPreview>(find.byType(ReaderFitPreview).first)
          .palette
          .isEink,
      isTrue,
    );
    expect(find.byKey(const Key('reader-background-black')), findsNothing);
  });

  testWidgets('阅读设置面板占据屏幕下 2/3，不撑满整屏', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await openSettings(tester);

    const screenHeight = 844.0;
    final sheetRect = tester.getRect(find.byType(ReaderSettingsSheet));
    expect(sheetRect.bottom, closeTo(screenHeight, 1.0));
    expect(
      sheetRect.height,
      closeTo(screenHeight * 2 / 3, 1.0),
      reason: '阅读设置面板应只占据屏幕下 2/3',
    );
  });

  testWidgets('从顶部横条下拉可直接关闭阅读设置面板（含滚动后）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await openSettings(tester);
    expect(find.byType(ReaderSettingsSheet), findsOneWidget);

    // 先向下滚动设置项，确认顶部横条仍在且下拉可以直接关闭。
    await tester.ensureVisible(
      find.byKey(const Key('reader-background-white')),
    );
    await tester.pumpAndSettle();

    final grabber = find.byKey(const Key('reader-settings-grabber'));
    expect(grabber, findsOneWidget);
    await tester.fling(grabber, const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(
      find.byType(ReaderSettingsSheet),
      findsNothing,
      reason: '从顶部横条下拉应直接关闭阅读设置面板',
    );
  });

  testWidgets('从顶部横条慢速拖过半也可关闭阅读设置面板', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await openSettings(tester);
    expect(find.byType(ReaderSettingsSheet), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('reader-settings-grabber')),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsNothing);
  });
}
