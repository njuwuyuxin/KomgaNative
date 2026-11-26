import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/widgets/shelf_pinch_detector.dart';
import 'package:material_ui/material_ui.dart';

/// UI-P2-7：双指捏合调封面档位。
void main() {
  Future<List<int>> pumpDetector(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShelfPinchDetector(
            enabled: enabled,
            onPinch: deltas.add,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
          ),
        ),
      ),
    );
    return deltas;
  }

  testWidgets('双指拉开放大一档，收拢缩小一档', (WidgetTester tester) async {
    final deltas = await pumpDetector(tester);

    final a = await tester.startGesture(const Offset(150, 300));
    final b = await tester.startGesture(const Offset(250, 300));
    await a.moveTo(const Offset(100, 300));
    await b.moveTo(const Offset(300, 300));
    await tester.pump();
    expect(deltas, <int>[1], reason: '一次手势只换一档：距离 100 → 200');

    // 抬手后再捏一次，收拢；起点 200 → 100。
    await a.up();
    await b.up();
    final c = await tester.startGesture(const Offset(100, 300), pointer: 3);
    final d = await tester.startGesture(const Offset(300, 300), pointer: 4);
    await c.moveTo(const Offset(150, 300));
    await d.moveTo(const Offset(250, 300));
    await tester.pump();
    expect(deltas, <int>[1, -1]);

    await c.up();
    await d.up();
  });

  testWidgets('单指拖动不触发（不能抢滚动）', (WidgetTester tester) async {
    final deltas = await pumpDetector(tester);

    await tester.dragFrom(const Offset(100, 300), const Offset(120, 0));
    await tester.pump();

    expect(deltas, isEmpty);
  });

  testWidgets('enabled=false 时完全不响应', (WidgetTester tester) async {
    final deltas = await pumpDetector(tester, enabled: false);

    final a = await tester.startGesture(const Offset(150, 300));
    final b = await tester.startGesture(const Offset(250, 300));
    await a.moveTo(const Offset(100, 300));
    await b.moveTo(const Offset(300, 300));
    await tester.pump();

    expect(deltas, isEmpty);
    await a.up();
    await b.up();
  });
}
