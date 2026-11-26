import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/widgets/page_curl.dart';
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

  Future<Uint8List> pngBytes(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF4080E0), BlendMode.src);
        final picture = recorder.endRecording();
        final pixels = await picture.toImage(4, 4);
        picture.dispose();
        final data = await pixels.toByteData(format: ui.ImageByteFormat.png);
        pixels.dispose();
        return data!.buffer.asUint8List();
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

  testWidgets('maxRetained=0 时只保留当前页，离开的页延后一帧释放', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final sheets = CurlSheets(maxRetained: 0);
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

  testWidgets('默认 LRU 保留已读历史页供回翻复用，超上限只淘汰最旧非保护页', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final sheets = CurlSheets(maxRetained: 3);
    addTearDown(sheets.dispose);
    final p0 = await image(tester);
    final p1 = await image(tester);
    final p2 = await image(tester);
    final p3 = await image(tester);

    await sheets.ensure(
      pages: <int>{0, 1},
      decode: (page) async => page == 0 ? p0 : p1,
      stillWanted: () => true,
    );
    await sheets.ensure(
      pages: <int>{2},
      decode: (page) async => p2,
      stillWanted: () => true,
    );
    // 仍在容量 3 内：之前看过的 0、1 全保留，回翻零延迟。
    expect(sheets.imageFor(0), same(p0));
    expect(sheets.imageFor(1), same(p1));
    expect(sheets.imageFor(2), same(p2));

    // 加入第 4 张且把 0 设为 pinned：0 被保护不淘汰，最旧的非保护页 1 被淘汰。
    await sheets.ensure(
      pages: <int>{3},
      pinned: <int>{0},
      decode: (page) async => p3,
      stillWanted: () => true,
    );
    expect(sheets.imageFor(0), same(p0));
    expect(sheets.imageFor(1), isNull);
    expect(sheets.imageFor(2), same(p2));
    expect(sheets.imageFor(3), same(p3));
    expect(p1.debugDisposed, isFalse);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(p1.debugDisposed, isTrue);
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

  testWidgets('并发解码：慢页卡住不阻塞同一批里其它页就绪', (tester) async {
    final sheets = CurlSheets();
    addTearDown(sheets.dispose);
    final slow = Completer<ui.Image?>();
    final fast = await image(tester);

    final loading = sheets.ensure(
      pages: <int>{0, 1},
      decode: (page) => page == 0 ? slow.future : Future<ui.Image?>.value(fast),
      stillWanted: () => true,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(sheets.imageFor(0), isNull);
    expect(sheets.imageFor(1), same(fast));

    final slowPixels = await image(tester);
    slow.complete(slowPixels);
    await loading;
    expect(sheets.imageFor(0), same(slowPixels));
  });

  testWidgets('clear 延后释放已有位图，并丢弃在途旧结果且不阻塞同页重解', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final sheets = CurlSheets();
    addTearDown(sheets.dispose);
    final existing = await image(tester);
    final stale = await image(tester);
    final fresh = await image(tester);
    final gate = Completer<ui.Image?>();

    await sheets.ensure(
      pages: <int>{0},
      decode: (page) async => existing,
      stillWanted: () => true,
    );
    final oldDecode = sheets.ensure(
      pages: <int>{0, 1},
      decode: (page) => gate.future,
      stillWanted: () => true,
    );

    sheets.clear();
    expect(sheets.imageFor(0), isNull);
    expect(existing.debugDisposed, isFalse);

    await sheets.ensure(
      pages: <int>{1},
      decode: (page) async => fresh,
      stillWanted: () => true,
    );
    expect(sheets.imageFor(1), same(fresh));

    gate.complete(stale);
    await oldDecode;
    expect(stale.debugDisposed, isTrue);
    expect(sheets.imageFor(1), same(fresh));

    tester.binding.scheduleFrame();
    await tester.pump();
    expect(existing.debugDisposed, isTrue);
  });

  testWidgets('ImageCache 同步桥接：已解码在 ImageCache 中的页零延迟借出且互不影响释放', (
    tester,
  ) async {
    final bytes = await pngBytes(tester);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 未进 ImageCache 前同步查询无副作用地返回 null。
    expect(trySyncImageFromCache(bytes), isNull);

    // 经 decodeThroughImageCache 解码一次后，ImageCache 已被同步暖热。
    final decoded = await tester.runAsync(() => decodeThroughImageCache(bytes));
    expect(decoded, isNotNull);
    expect(
      PaintingBinding.instance.imageCache.containsKey(MemoryImage(bytes)),
      isTrue,
    );

    // 再次同步取用：零异步等待立即返回独立 clone 句柄。
    final borrowed = trySyncImageFromCache(bytes);
    expect(borrowed, isNotNull);
    expect(borrowed!.width, 4);

    // 清空 ImageCache 不会把卷页侧克隆出的句柄作废；释放克隆句柄也不影响另一份。
    PaintingBinding.instance.imageCache.clear();
    expect(borrowed.debugDisposed, isFalse);
    decoded!.dispose();
    expect(borrowed.debugDisposed, isFalse);
    borrowed.dispose();
    expect(borrowed.debugDisposed, isTrue);
  });
}
