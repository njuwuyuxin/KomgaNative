import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_reader.dart';

/// 不使用 pumpAndSettle：逐帧检查着色器 → 普通图片交接，不能吞掉解码空窗。
void main() {
  for (final rtl in <bool>[true, false]) {
    for (final forward in <bool>[true, false]) {
      testWidgets('冷图片缓存交接 rtl=$rtl forward=$forward', (tester) async {
        final repository = _SolidPages();
        await tester.runAsync(() async {
          await PageCurlProgram.ensureLoaded();
          await repository.prepare();
        });
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var spread = <int>[2, 3];
        final key = GlobalKey<ReaderPagedViewState>();
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              readerRepositoryProvider.overrideWithValue(repository),
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: StatefulBuilder(
                builder: (context, update) => RepaintBoundary(
                  key: captureKey,
                  child: ColoredBox(
                    color: const Color(0xFF000000),
                    child: ReaderPagedView(
                      key: key,
                      bookId: 'b1',
                      pages: repository.info,
                      spread: spread,
                      previousSpread: spread.first > 0
                          ? <int>[spread.first - 2, spread.first - 1]
                          : null,
                      nextSpread: spread.last < 5
                          ? <int>[spread.last + 1, spread.last + 2]
                          : null,
                      rightToLeft: rtl,
                      palette: ReaderPalette.dark,
                      onToggleChrome: () {},
                      onTurn: (delta) => update(() {
                        spread = <int>[
                          spread.first + 2 * delta,
                          spread.last + 2 * delta,
                        ];
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // 给独立的卷页解码真实执行时间，但不预热 MemoryImage。
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        key.currentState!.turn(forward ? 1 : -1);
        await tester.pump();
        expect(key.currentState!.debugHinged, isTrue);
        await tester.pump(const Duration(milliseconds: 384));
        await _capture(tester, captureKey, 'before', rtl, forward);
        await tester.pump(const Duration(milliseconds: 32));
        expect(spread, forward ? <int>[4, 5] : <int>[0, 1]);
        // Image.memory 的首次解码可能还没返回，此时仍要有当前目标页的像素。
        final bytes = await _capture(
          tester,
          captureKey,
          'handoff',
          rtl,
          forward,
        );
        final order = rtl ? spread.reversed.toList() : spread;
        for (var side = 0; side < 2; side++) {
          final center = tester
              .getRect(find.byKey(Key('reader-image-${order[side]}')))
              .center;
          final pixel = (center.dy.round() * 800 + center.dx.round()) * 4;
          final color = repository.colors[order[side]];
          expect(bytes[pixel], closeTo(color.r, 2), reason: 'side=$side red');
          expect(
            bytes[pixel + 1],
            closeTo(color.g, 2),
            reason: 'side=$side green',
          );
          expect(
            bytes[pixel + 2],
            closeTo(color.b, 2),
            reason: 'side=$side blue',
          );
        }
        await expectLater(
          find.byKey(captureKey),
          matchesGoldenFile(
            'goldens/reader_curl@tablet_dark_${rtl ? "rtl" : "ltr"}_${forward ? "forward" : "back"}_handoff.png',
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await _capture(tester, captureKey, 'after', rtl, forward);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('底层冷页还没解码时不启动卷页，放行后恢复卷页', (tester) async {
    final repository = _SolidPages();
    final gate = Completer<void>();
    repository.pageGates[6] = gate;
    await tester.runAsync(() async {
      await PageCurlProgram.ensureLoaded();
      await repository.prepare();
    });
    final key = GlobalKey<ReaderPagedViewState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [readerRepositoryProvider.overrideWithValue(repository)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderPagedView(
            key: key,
            bookId: 'b1',
            pages: repository.info,
            spread: const [2, 3],
            nextSpread: const [4, 5],
            rightToLeft: true,
            palette: ReaderPalette.dark,
            onTurn: (delta) {},
            onToggleChrome: () {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    key.currentState!.turn(1);
    await tester.pump();
    expect(key.currentState!.debugCurling, isFalse, reason: '有纸背但底层还冷，不能卷出黑半页');
    await tester.pump(const Duration(milliseconds: 500));
    gate.complete();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    key.currentState!.turn(1);
    await tester.pump();
    expect(key.currentState!.debugHinged, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<Uint8List> _capture(
  WidgetTester tester,
  GlobalKey key,
  String stage,
  bool rtl,
  bool forward,
) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    // 设置环境变量时才导出帧，不把本地诊断文件放进仓库。
    final directory = Platform.environment['CURL_CAPTURE_DIR'];
    if (directory != null) {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '$directory/${rtl ? "rtl" : "ltr"}-${forward ? "forward" : "back"}-$stage.png',
      ).writeAsBytes(png.buffer.asUint8List());
    }
    image.dispose();
    return rgba.buffer.asUint8List();
  }))!;
}

/// 不循环复用字节实例：每一页都是独立 MemoryImage key，保证目标页是冷解码。
class _SolidPages extends FakeReaderRepository {
  _SolidPages() : super(pageCount: 6);

  final colors = <({int r, int g, int b})>[
    (r: 240, g: 80, b: 70),
    (r: 80, g: 200, b: 100),
    (r: 80, g: 120, b: 240),
    (r: 240, g: 190, b: 70),
    (r: 170, g: 90, b: 220),
    (r: 60, g: 200, b: 220),
  ];
  final Map<int, Uint8List> _pages = <int, Uint8List>{};
  List<PageInfo> get info => <PageInfo>[
    for (var i = 1; i <= 6; i++)
      PageInfo(number: i, width: 1000, height: 1500, mediaType: 'image/png'),
  ];

  Future<void> prepare() async {
    for (var i = 0; i < colors.length; i++) {
      final color = colors[i];
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(
        Color.fromARGB(255, color.r, color.g, color.b),
        BlendMode.src,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 600);
      picture.dispose();
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      _pages[i + 1] = data.buffer.asUint8List();
      image.dispose();
    }
  }

  @override
  Uint8List? cachedPageImage(String bookId, int page) {
    final gate = pageGates[page];
    return gate != null && !gate.isCompleted ? null : _pages[page];
  }

  @override
  Future<Uint8List> pageImage(String bookId, int page) async {
    pageImageCalls++;
    final gate = pageGates[page];
    if (gate != null) await gate.future;
    return _pages[page]!;
  }
}
