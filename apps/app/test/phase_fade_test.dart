import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/widgets/phase_fade.dart';
import 'package:material_ui/material_ui.dart';

/// UI-P2-8 的入场淡入。
///
/// 这里钉的是一个**只在墨水屏 / "减少动态效果"上出现**的问题：
/// `PhaseFade` 在 phase 变化时把控制器归零再 `forward()`，而动画被禁用时
/// `forward()` 不推进——书架就停在 opacity 0，"有数据但看不见"。
/// 黄金图 `library@eink` 与 `library_error@eink` 曾经是两张一模一样的空页面。
void main() {
  Widget host(
    String phase, {
    required ThemeData theme,
    bool disableAnimations = false,
  }) => MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            PhaseFade(
              phase: phase,
              slivers: <Widget>[SliverToBoxAdapter(child: Text(phase))],
            ),
          ],
        ),
      ),
    ),
  );

  double opacityOf(WidgetTester tester) => tester
      .widget<SliverFadeTransition>(find.byType(SliverFadeTransition))
      .opacity
      .value;

  testWidgets('普通主题：phase 变化会淡入，结束在完全可见', (WidgetTester tester) async {
    await tester.pumpWidget(host('loading', theme: AppTheme.light()));
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);

    await tester.pumpWidget(host('content', theme: AppTheme.light()));
    await tester.pump();
    expect(opacityOf(tester), lessThan(1), reason: '换了 phase 应该从透明开始淡入');

    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('墨水屏：phase 变化直接到终值，不会停在透明态', (WidgetTester tester) async {
    await tester.pumpWidget(host('loading', theme: AppTheme.eink()));
    await tester.pump();
    expect(opacityOf(tester), 1);

    await tester.pumpWidget(host('content', theme: AppTheme.eink()));
    await tester.pump();
    // 这条断言就是书架空白页的回归测试：值必须立刻是 1。
    expect(opacityOf(tester), 1);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('系统"减少动态效果"：同上（即使主题是浅色）', (WidgetTester tester) async {
    await tester.pumpWidget(
      host('loading', theme: AppTheme.light(), disableAnimations: true),
    );
    await tester.pump();

    await tester.pumpWidget(
      host('content', theme: AppTheme.light(), disableAnimations: true),
    );
    await tester.pump();
    expect(opacityOf(tester), 1);
  });
}
