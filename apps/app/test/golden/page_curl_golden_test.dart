import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// 卷页着色器的逐帧基线：起手（只翘起页脚）、中段（斜卷、背面压在页上）、
/// 收尾（卷筒滑出书脊），以及往回翻的中段和书脊在左的镜像。
///
/// 纸面用合成位图（网格 + 色块），一眼就能看出纹理是否被正确地拉伸/翻转。
void main() {
  setUpAll(() async {
    await PageCurlProgram.ensureLoaded();
  });

  /// 画一张"页面"：浅底、深色网格、左下角红块、右上角蓝块。
  Future<ui.Image> syntheticSheet(int w, int h) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFEDE7DA),
    );
    final ink = Paint()
      ..color = const Color(0xFF2E2A25)
      ..strokeWidth = 3;
    for (var x = 0.0; x <= w; x += w / 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, h.toDouble()), ink);
    }
    for (var y = 0.0; y <= h; y += h / 12) {
      canvas.drawLine(Offset(0, y), Offset(w.toDouble(), y), ink);
    }
    canvas
      ..drawRect(
        Rect.fromLTWH(0, h * 0.8, w * 0.3, h * 0.2),
        Paint()..color = const Color(0xFFC0392B),
      )
      ..drawRect(
        Rect.fromLTWH(w * 0.7, 0, w * 0.3, h * 0.15),
        Paint()..color = const Color(0xFF2E6DB4),
      )
      ..drawCircle(
        Offset(w * 0.5, h * 0.5),
        w * 0.18,
        Paint()..color = const Color(0xFF3B3B3B),
      );
    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  Future<void> pumpCurl(
    WidgetTester tester, {
    required String name,
    required bool forward,
    required double turn,
    bool mirrored = false,
  }) async {
    const size = GoldenSizes.phone;
    tester.view.physicalSize = size * kGoldenDevicePixelRatio;
    tester.view.devicePixelRatio = kGoldenDevicePixelRatio;
    addTearDown(tester.view.reset);

    final sheet = (await tester.runAsync(() => syntheticSheet(600, 900)))!;
    addTearDown(sheet.dispose);

    // 页面在屏幕中间略留边，和阅读器里"fit 到视口"的效果一致。
    const rect = Rect.fromLTWH(15, 130, 360, 540);
    final exitX = mirrored ? rect.right : size.width - rect.left;
    final motion = CurlMotion(
      forward: forward,
      width: rect.width,
      height: rect.height,
      exitX: exitX,
    );
    final frame = motion.frame(motion.fingerAt(turn), mirrored: mirrored);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: const Key('curl'),
          child: Stack(
            children: <Widget>[
              // 下层：相邻页（纯色，方便看影子）。
              Positioned.fill(child: Container(color: const Color(0xFF1C1B1A))),
              Positioned.fromRect(
                rect: rect,
                child: Container(color: const Color(0xFFB9C7B4)),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: PageCurlPainter(
                    sheet: sheet,
                    sheetRect: rect,
                    frame: frame,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const Key('curl')),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('page_curl@start', (WidgetTester tester) async {
    await pumpCurl(tester, name: 'page_curl@start', forward: true, turn: 0.1);
  });

  testWidgets('page_curl@middle', (WidgetTester tester) async {
    await pumpCurl(tester, name: 'page_curl@middle', forward: true, turn: 0.4);
  });

  testWidgets('page_curl@late', (WidgetTester tester) async {
    await pumpCurl(tester, name: 'page_curl@late', forward: true, turn: 0.75);
  });

  testWidgets('page_curl@back_middle', (WidgetTester tester) async {
    await pumpCurl(
      tester,
      name: 'page_curl@back_middle',
      forward: false,
      turn: 0.6,
    );
  });

  testWidgets('page_curl@mirrored', (WidgetTester tester) async {
    await pumpCurl(
      tester,
      name: 'page_curl@mirrored',
      forward: true,
      turn: 0.4,
      mirrored: true,
    );
  });
}
