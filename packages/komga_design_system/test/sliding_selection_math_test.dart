import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/src/components/sliding_selection_math.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const slots = <Rect>[
    Rect.fromLTWH(0, 0, 100, 40),
    Rect.fromLTWH(104, 0, 100, 40),
    Rect.fromLTWH(208, 0, 120, 40),
  ];

  group('resolveContinuousSelection', () {
    test('非法输入（0 槽位或非有限值）返回 null', () {
      expect(
        resolveContinuousSelection(
          position: 0,
          itemCount: 0,
          slots: const <Rect>[],
          pillInset: EdgeInsets.zero,
          motionEnabled: true,
        ),
        isNull,
      );
      for (final bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          resolveContinuousSelection(
            position: bad,
            itemCount: 3,
            slots: slots,
            pillInset: EdgeInsets.zero,
            motionEnabled: true,
          ),
          isNull,
        );
      }
    });

    test('端点精确命中对应槽位，中间值在相邻变宽槽位间线性插值', () {
      final at0 = resolveContinuousSelection(
        position: 0,
        itemCount: 3,
        slots: slots,
        pillInset: const EdgeInsets.all(4),
        motionEnabled: true,
      )!;
      expect(at0.pillRect, const Rect.fromLTWH(4, 4, 92, 32));
      expect(at0.weights, <double>[1, 0, 0]);

      final at15 = resolveContinuousSelection(
        position: 1.5,
        itemCount: 3,
        slots: slots,
        pillInset: EdgeInsets.zero,
        motionEnabled: true,
      )!;
      expect(at15.pillRect, Rect.lerp(slots[1], slots[2], 0.5));
      expect(at15.weights, <double>[0, 0.5, 0.5]);
    });

    test('越界值钳位到两端；未量完槽位时 pillRect 为 null 但权重正常', () {
      final under = resolveContinuousSelection(
        position: -0.5,
        itemCount: 3,
        slots: slots,
        pillInset: EdgeInsets.zero,
        motionEnabled: true,
      )!;
      expect(under.pillRect, slots.first);
      expect(under.weights, <double>[1, 0, 0]);

      final over = resolveContinuousSelection(
        position: 5,
        itemCount: 3,
        slots: slots,
        pillInset: EdgeInsets.zero,
        motionEnabled: true,
      )!;
      expect(over.pillRect, slots.last);
      expect(over.weights, <double>[0, 0, 1]);

      final unmeasured = resolveContinuousSelection(
        position: 0.4,
        itemCount: 3,
        slots: const <Rect>[],
        pillInset: EdgeInsets.zero,
        motionEnabled: true,
      )!;
      expect(unmeasured.pillRect, isNull);
      expect(unmeasured.weights[0], closeTo(0.6, 1e-9));
      expect(unmeasured.weights[1], closeTo(0.4, 1e-9));
      expect(unmeasured.weights[2], 0);
    });

    test('墨水屏 / 减少动态效果按四舍五入瞬切，不输出中间权重', () {
      final beforeHalf = resolveContinuousSelection(
        position: 0.49,
        itemCount: 3,
        slots: slots,
        pillInset: EdgeInsets.zero,
        motionEnabled: false,
      )!;
      expect(beforeHalf.pillRect, slots[0]);
      expect(beforeHalf.weights, <double>[1, 0, 0]);

      final atHalf = resolveContinuousSelection(
        position: 0.5,
        itemCount: 3,
        slots: slots,
        pillInset: EdgeInsets.zero,
        motionEnabled: false,
      )!;
      expect(atHalf.pillRect, slots[1]);
      expect(atHalf.weights, <double>[0, 1, 0]);
    });

    test('单槽位退化正常', () {
      final single = resolveContinuousSelection(
        position: 0.8,
        itemCount: 1,
        slots: <Rect>[slots.first],
        pillInset: EdgeInsets.zero,
        motionEnabled: true,
      )!;
      expect(single.pillRect, slots.first);
      expect(single.weights, <double>[1]);
    });
  });

  group('targetSlotWeights / lerpSlotWeights', () {
    test('处理 null / 越界下标与长度不匹配回退', () {
      expect(targetSlotWeights(2, null), <double>[0, 0]);
      expect(targetSlotWeights(2, -1), <double>[0, 0]);
      expect(targetSlotWeights(2, 5), <double>[0, 0]);
      expect(targetSlotWeights(2, 1), <double>[0, 1]);
      expect(
        lerpSlotWeights(const <double>[1], const <double>[0, 1], 2, 0.5, 1),
        <double>[0, 1],
      );
      expect(
        lerpSlotWeights(const <double>[1, 0], const <double>[0, 1], 2, 1.2, 1),
        <double>[0, 1],
      );
    });
  });
}
