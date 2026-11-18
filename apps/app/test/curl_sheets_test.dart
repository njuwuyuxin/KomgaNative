import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<ui.Image> image(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF80C060), BlendMode.src);
        final picture = recorder.endRecording();
        final pixels = await picture.toImage(2, 2);
        picture.dispose();
        return pixels;
      }))!;

  testWidgets('重复预加载同一页合并解码，不替换已借出的位图', (tester) async {
    final sheets = CurlSheets();
    addTearDown(sheets.dispose);
    final gate = Completer<ui.Image?>();
    var calls = 0;
    Future<ui.Image?> decode(int page) {
      calls++;
      return gate.future;
    }

    final first = sheets.ensure(
      pages: <int>{0},
      decode: decode,
      stillWanted: () => true,
    );
    final second = sheets.ensure(
      pages: <int>{0},
      decode: decode,
      stillWanted: () => true,
    );
    expect(calls, 1);
    final pixels = await image(tester);
    gate.complete(pixels);
    await Future.wait(<Future<void>>[first, second]);
    expect(sheets.imageFor(0), same(pixels));
    await sheets.ensure(
      pages: <int>{0},
      decode: decode,
      stillWanted: () => true,
    );
    expect(calls, 1);
    expect(sheets.imageFor(0), same(pixels));
  });

  testWidgets('翻走后当前页位图保留，离开的页延后一帧释放', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final sheets = CurlSheets();
    addTearDown(sheets.dispose);
    final a = await image(tester);
    final b = await image(tester);
    await sheets.ensure(
      pages: <int>{0, 1},
      decode: (page) async => page == 0 ? a : b,
      stillWanted: () => true,
    );
    await sheets.ensure(
      pages: <int>{1},
      decode: (page) async => throw StateError('不应重复解码'),
      stillWanted: () => true,
    );
    expect(sheets.imageFor(0), isNull);
    expect(sheets.imageFor(1), same(b));
    expect(a.debugDisposed, isFalse);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(a.debugDisposed, isTrue);
    expect(b.debugDisposed, isFalse);
  });

  testWidgets('过期回调不清掉新屏位图，过期解码结果也不进入缓存', (tester) async {
    final sheets = CurlSheets();
    addTearDown(sheets.dispose);
    final old = await image(tester);
    final current = await image(tester);
    final gate = Completer<ui.Image?>();
    var oldWanted = true;
    final loading = sheets.ensure(
      pages: <int>{0},
      decode: (page) => gate.future,
      stillWanted: () => oldWanted,
    );
    oldWanted = false;
    await sheets.ensure(
      pages: <int>{1},
      decode: (page) async => current,
      stillWanted: () => true,
    );
    gate.complete(old);
    await loading;
    expect(old.debugDisposed, isTrue);
    expect(sheets.imageFor(0), isNull);
    await sheets.ensure(
      pages: <int>{0},
      decode: (page) async => null,
      stillWanted: () => false,
    );
    expect(sheets.imageFor(1), same(current));
  });

  testWidgets('销毁后仍在解码的结果释放，不重新填入缓存', (tester) async {
    final sheets = CurlSheets();
    final pixels = await image(tester);
    final gate = Completer<ui.Image?>();
    final loading = sheets.ensure(
      pages: <int>{0},
      decode: (page) => gate.future,
      stillWanted: () => true,
    );
    sheets.dispose();
    gate.complete(pixels);
    await loading;
    expect(pixels.debugDisposed, isTrue);
    expect(sheets.imageFor(0), isNull);
  });
}
