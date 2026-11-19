import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P1-5 动态背景：取页边主色、白色背景、以及"墨水屏不给动态选项"。
void main() {
  Color backgroundOf(WidgetTester tester) {
    // 读**渲染中**的 DecoratedBox：AnimatedContainer 自己的 decoration 是目标值，
    // 过渡到一半时它已经是白色了，看不到中间色。
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const Key('reader-background')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration?;
    return decoration?.color ??
        decoration?.gradient?.colors.first ??
        Colors.transparent;
  }

  /// 提色是**真实异步解码**，假时钟推不动它。
  Future<void> settleEdgeColor(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认黑色背景', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    expect(backgroundOf(tester), ReaderPalette.dark.background);
  });

  testWidgets('沉浸式：左右页边色成渐变（P3-7）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageNames: const <String>['edge_split']),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        background: ReaderBackgroundChoice.immersive,
      ),
    );
    await settleEdgeColor(tester);

    final box = tester.widget<AnimatedContainer>(
      find.byKey(const Key('reader-background')),
    );
    final gradient = (box.decoration as BoxDecoration).gradient!;
    expect(gradient.colors, hasLength(2));
    expect(
      gradient.colors.first.r,
      greaterThan(gradient.colors.last.r),
      reason: '左红右蓝',
    );
    expect(gradient.colors.last.b, greaterThan(gradient.colors.first.b));
  });

  testWidgets('白色背景：阅读区变白，chrome 文字仍是白色', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(background: ReaderBackgroundChoice.white),
    );

    expect(backgroundOf(tester), ReaderPalette.white.background);
    // chrome 压在深色毛玻璃上，不能跟着白底变黑字。
    final title = tester.widget<Text>(find.text('Vol. 1'));
    expect(title.style?.color, ReaderPalette.white.foreground);
  });

  testWidgets('动态背景：取页边色（青绿合成页 → 青绿底）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageNames: const <String>['edge_teal']),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        background: ReaderBackgroundChoice.dynamic,
      ),
    );
    await settleEdgeColor(tester);

    final background = backgroundOf(tester);
    // 合成页的页边是 (38, 110, 118)；降采样后取平均会有几格误差。
    expect((background.r * 255).round(), closeTo(38, 24));
    expect((background.g * 255).round(), closeTo(110, 24));
    expect((background.b * 255).round(), closeTo(118, 24));
    expect(
      background,
      isNot(ReaderPalette.dark.background),
      reason: '真的换了底色，不是退回黑色',
    );
  });

  testWidgets('动态背景取不到颜色时退回黑色（不黑屏、不报错）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageNames: const <String>['edge_teal']),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        background: ReaderBackgroundChoice.dynamic,
      ),
    );
    // 还没跑真实时间：颜色还没算出来，此时必须是确定的黑色。
    expect(backgroundOf(tester), ReaderPalette.dark.background);
  });

  testWidgets('设置面板里能切到"跟随画面"，并落盘', (WidgetTester tester) async {
    final store = await pumpReader(tester, book: demoReaderBook());
    await pickOption(tester, 'reader-background-dynamic');

    expect(store.prefs!.background, ReaderBackgroundChoice.dynamic);
  });

  testWidgets('换背景色是交叉渐变，不是瞬切', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    expect(backgroundOf(tester), ReaderPalette.dark.background);

    await openSettings(tester);
    final option = find.byKey(const Key('reader-background-white'));
    await revealInSheet(tester, option);
    await tester.tap(option);
    await tester.pump();
    // 过渡到一半：既不是旧色也不是新色。
    await tester.pump(const Duration(milliseconds: 100));
    final mid = backgroundOf(tester);
    expect(mid, isNot(ReaderPalette.white.background));
    expect(mid, isNot(ReaderPalette.dark.background));

    await tester.pumpAndSettle();
    expect(backgroundOf(tester), ReaderPalette.white.background);
  });

  testWidgets('墨水屏不提供背景选项（固定白底）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), forceEink: true);
    await openSettings(tester);

    expect(find.text('BACKGROUND'), findsNothing);
    expect(find.byKey(const Key('reader-background-dynamic')), findsNothing);
    expect(backgroundOf(tester), AppTheme.einkPaper);
  });

  testWidgets('墨水屏即使存档里是"动态"也用纸色', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      forceEink: true,
      initialPrefs: const ReaderPrefs(
        background: ReaderBackgroundChoice.dynamic,
      ),
    );
    await settleEdgeColor(tester);

    expect(backgroundOf(tester), AppTheme.einkPaper);
  });
}
