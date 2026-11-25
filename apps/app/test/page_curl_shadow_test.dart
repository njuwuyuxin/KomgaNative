import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 回归测试：单页卷页时纸页边缘外的卷筒阴影不得出现离散采样导致的条状阶梯带纹，
/// 也不得在纸页上方跨轴线 d = 0 处产生竖向硬截断。
void main() {
  setUpAll(() async {
    await PageCurlProgram.ensureLoaded();
  });

  Future<ui.Image> solidSheet(int w, int h, Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = color,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    return image;
  }

  /// 在纯白底上绘制单页卷页，返回 RGBA 字节与画布尺寸。
  Future<Uint8List> renderCurlRgba({
    required Size canvasSize,
    required Rect sheetRect,
    required CurlFrame frame,
    required ui.Image sheet,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & canvasSize,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    PageCurlPainter(
      sheet: sheet,
      sheetRect: sheetRect,
      frame: frame,
    ).paint(canvas, canvasSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasSize.width.round(),
      canvasSize.height.round(),
    );
    picture.dispose();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return data.buffer.asUint8List();
  }

  int lumaAt(Uint8List rgba, int width, int x, int y) {
    final idx = (y * width + x) * 4;
    return rgba[idx];
  }

  testWidgets('纸页上缘外侧阴影沿纵向与跨轴线均连续，无阶梯条纹', (WidgetTester tester) async {
    const canvasSize = Size(390, 800);
    // 复现真实场景：被卷白页比底页更矮，纸页上缘上方是大片亮色底页。
    const sheetRect = Rect.fromLTWH(0, 170, 390, 480);
    final sheet = (await tester.runAsync(
      () => solidSheet(390, 480, const Color(0xFFFFFFFF)),
    ))!;
    addTearDown(sheet.dispose);

    for (final mirrored in <bool>[false, true]) {
      for (final turn in <double>[0.45, 0.6, 0.75]) {
        final exitX = mirrored ? sheetRect.right : canvasSize.width;
        final motion = CurlMotion(
          forward: true,
          width: sheetRect.width,
          height: sheetRect.height,
          exitX: exitX,
        );
        final frame = motion.frame(motion.fingerAt(turn), mirrored: mirrored);
        final rgba = (await tester.runAsync(
          () => renderCurlRgba(
            canvasSize: canvasSize,
            sheetRect: sheetRect,
            frame: frame,
            sheet: sheet,
          ),
        ))!;

        final w = canvasSize.width.round();
        // 扫描纸页上缘上方 6..90px 的纯白底页区域（避开纸面抗锯齿 1px 边与卷起尖端）。
        // 确认这里确实有可见的软阴影，且任意相邻像素间亮度跳变不超过平滑阈值。
        var maxVerticalJump = 0;
        var maxHorizontalJump = 0;
        var minLuma = 255;

        // 找出每一行完全不与卷起纸面（含纸背）重叠的安全上界：
        // 纸面最高在 y = sheetRect.top，翻起尖端最高不会超过 sheetRect.top - 2*r。
        final safeBottomY = (sheetRect.top - 2.2 * frame.radius).floor().clamp(
          10,
          sheetRect.top.floor() - 6,
        );
        final safeTopY = math.max(8, safeBottomY - 80);

        for (var y = safeTopY; y < safeBottomY; y++) {
          for (var x = 8; x < w - 8; x++) {
            final cur = lumaAt(rgba, w, x, y);
            if (cur < minLuma) minLuma = cur;
            final down = lumaAt(rgba, w, x, y + 1);
            final right = lumaAt(rgba, w, x + 1, y);
            maxVerticalJump = math.max(maxVerticalJump, (down - cur).abs());
            maxHorizontalJump = math.max(
              maxHorizontalJump,
              (right - cur).abs(),
            );
          }
        }

        // 旧实现 5-tap 离散采样在阶梯处单像素跳变约 15~22/255，且 d=0 处竖向截断跳变更大。
        expect(
          maxVerticalJump,
          lessThanOrEqualTo(4),
          reason:
              'mirrored=$mirrored turn=$turn 纸页上缘外阴影出现纵向阶梯跳变 ($maxVerticalJump)',
        );
        expect(
          maxHorizontalJump,
          lessThanOrEqualTo(4),
          reason:
              'mirrored=$mirrored turn=$turn 纸页上缘外阴影出现跨轴线横向跳变 ($maxHorizontalJump)',
        );
        expect(
          minLuma,
          lessThan(252),
          reason: 'mirrored=$mirrored turn=$turn 应存在柔和的卷筒阴影而非完全透明',
        );
      }
    }
  });

  testWidgets('纯水平拖页时，露出底页的上下两端阴影均平滑无条状阶梯', (WidgetTester tester) async {
    const canvasSize = Size(390, 800);
    const sheetRect = Rect.fromLTWH(0, 140, 390, 520);
    final sheet = (await tester.runAsync(
      () => solidSheet(390, 520, const Color(0xFFFFFFFF)),
    ))!;
    addTearDown(sheet.dispose);

    for (final mirrored in <bool>[false, true]) {
      // 纯水平拖动（fingerY == height）使卷轴严格竖直（u = (±1, 0)），
      // 复现上下两端同时出现阶梯条状阴影的最明显工况。
      final frame = solveCurl(
        fingerX: sheetRect.width * 0.7,
        fingerY: sheetRect.height,
        width: sheetRect.width,
        height: sheetRect.height,
        mirrored: mirrored,
      );
      final rgba = (await tester.runAsync(
        () => renderCurlRgba(
          canvasSize: canvasSize,
          sheetRect: sheetRect,
          frame: frame,
          sheet: sheet,
        ),
      ))!;

      final w = canvasSize.width.round();
      // 露出的底页区域（避开卷筒外沿 4px）：RTL 在卷筒左侧，LTR 在卷筒右侧。
      final axisCanvasX = sheetRect.left + frame.axisX;
      final startX = mirrored
          ? (axisCanvasX + frame.radius + 4).ceil().clamp(0, w - 1)
          : 4;
      final endX = mirrored
          ? w - 4
          : (axisCanvasX - frame.radius - 4).floor().clamp(0, w - 1);
      expect(endX - startX, greaterThan(20));

      var maxTopJump = 0;
      var maxBottomJump = 0;
      var minTopLuma = 255;
      var minBottomLuma = 255;

      final topStart = sheetRect.top.ceil() + 2;
      final topEnd = topStart + 90;
      final bottomEnd = sheetRect.bottom.floor() - 2;
      final bottomStart = bottomEnd - 90;

      for (var x = startX; x <= endX; x++) {
        for (var y = topStart; y < topEnd; y++) {
          final cur = lumaAt(rgba, w, x, y);
          final next = lumaAt(rgba, w, x, y + 1);
          if (cur < minTopLuma) minTopLuma = cur;
          maxTopJump = math.max(maxTopJump, (next - cur).abs());
        }
        for (var y = bottomStart; y < bottomEnd; y++) {
          final cur = lumaAt(rgba, w, x, y);
          final next = lumaAt(rgba, w, x, y + 1);
          if (cur < minBottomLuma) minBottomLuma = cur;
          maxBottomJump = math.max(maxBottomJump, (next - cur).abs());
        }
      }

      // 旧 5-tap 实现在上下两端距边 0.5*soft / 1.0*soft 处单像素跳变约 21/255。
      expect(
        maxTopJump,
        lessThanOrEqualTo(3),
        reason: 'mirrored=$mirrored 上端露出底页阴影出现条状阶梯跳变 ($maxTopJump)',
      );
      expect(
        maxBottomJump,
        lessThanOrEqualTo(3),
        reason: 'mirrored=$mirrored 下端露出底页阴影出现条状阶梯跳变 ($maxBottomJump)',
      );
      expect(minTopLuma, lessThan(220), reason: '上端附近应保留自然卷筒阴影');
      expect(minBottomLuma, lessThan(220), reason: '下端附近应保留自然卷筒阴影');
    }
  });
}
