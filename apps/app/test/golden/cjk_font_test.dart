import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// 守住"中文黄金图里的汉字不是占位方块"。
///
/// 截图里看不出字形对不对（尤其 Agent 没法看图时），所以直接量：
/// 测试字体加载后，汉字应由 NotoSansSC 回退渲染——字形的墨迹分布与"豆腐块"
/// （空心矩形，四边都有墨、中心空）不同。这里用更稳的判据：
/// 同一个汉字在"带回退"和"不带回退"两种样式下的绘制结果不同。
void main() {
  setUpAll(loadAppFonts);

  testWidgets('汉字走 NotoSansSC 回退，而不是占位字形', (WidgetTester tester) async {
    final theme = withTestFont(ThemeData());
    // ThemeData 的原始 textTheme 没有字号（字号由 Theme.of 本地化时补上），这里显式给。
    final withFallback = theme.textTheme.bodyMedium!.copyWith(fontSize: 20);
    final withoutFallback = withFallback.copyWith(
      fontFamilyFallback: const <String>[],
    );

    double widthOf(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: '中文设置', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    expect(withFallback.fontFamilyFallback, contains('NotoSansSC'));
    // 回退字体的汉字是全角（≈ 1em），占位字形窄得多；两者宽度必然不同。
    expect(widthOf(withFallback), isNot(widthOf(withoutFallback)));
    expect(
      widthOf(withFallback),
      moreOrLessEquals(4 * withFallback.fontSize!, epsilon: 2),
    );
  });
}
