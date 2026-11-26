import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/src/widgets/edge_swipe_back.dart';
import 'package:material_ui/material_ui.dart';

/// UI-P2-3：边缘右滑返回。
///
/// 真正的交互式 Cupertino 返回没有做（Flutter 3.47 起 cupertino.dart 废弃），
/// 这里钉的是"边缘 24px 内、拖过阈值就 pop；墨水屏不做手势"。
void main() {
  Future<void> pumpTwoRoutes(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const EdgeSwipeBack(
                      child: Scaffold(body: Center(child: Text('second'))),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  }

  testWidgets('从左边缘往右拖会返回上一页', (WidgetTester tester) async {
    await pumpTwoRoutes(tester);

    // 起点必须在 24px 的手势条里；拖过 64px 阈值。
    await tester.dragFrom(const Offset(2, 400), const Offset(140, 0));
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('从页面中间拖不会返回（不能抢页面的横向手势）', (WidgetTester tester) async {
    await pumpTwoRoutes(tester);

    await tester.dragFrom(const Offset(200, 400), const Offset(140, 0));
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('墨水屏不做边缘手势（仍然可以系统返回）', (WidgetTester tester) async {
    await pumpTwoRoutes(tester, theme: AppTheme.eink());

    await tester.dragFrom(const Offset(2, 400), const Offset(140, 0));
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
    expect(find.byKey(const Key('edge-swipe-back')), findsNothing);
  });
}
