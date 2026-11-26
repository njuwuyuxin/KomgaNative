import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/widgets/page_curl.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_reader.dart';

/// 单页：底层相邻页还没解码时**仍然卷页**，掀开后露出的是它自己的加载态。
///
/// 这条是"退化范围只看纸面"的视觉契约，两帧各钉一半：
/// - `_mid`：纸真的在卷（不是整屏平移），哪怕下层什么都没有；
/// - `_reveal`：卷走之后露出的是那一页的加载态，不是黑块、也不是空白。
void main() {
  testWidgets('单页底层冷页也卷页：卷动中段与露出的加载态', (WidgetTester tester) async {
    final repository = _SolidPages();
    // 第 2 页（下一屏）挂住：纸面照常卷，掀开后露出它的转圈。
    final gate = Completer<void>();
    repository.pageGates[2] = gate;
    await tester.runAsync(() async {
      await PageCurlProgram.ensureLoaded();
      await repository.prepare();
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<ReaderPagedViewState>();
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          readerRepositoryProvider.overrideWithValue(repository),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: captureKey,
            child: ColoredBox(
              color: ReaderPalette.dark.background,
              child: ReaderPagedView(
                key: key,
                bookId: 'b1',
                pages: repository.info,
                spread: const <int>[0],
                nextSpread: const <int>[1],
                rightToLeft: true,
                palette: ReaderPalette.dark,
                onTurn: (int delta) {},
                onToggleChrome: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // 给卷页位图真实解码时间；第 2 页被闸住，队列停在那里，不影响第 1 页。
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }

    key.currentState!.turn(1);
    // 第一个 tick 只让控制器起表。
    await tester.pump();
    expect(key.currentState!.debugCurling, isTrue, reason: '纸面就绪就该卷页，不等底层');

    await tester.pump(const Duration(milliseconds: 214));
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/reader_curl@tablet_dark_cold_under_mid.png'),
    );

    await tester.pump(const Duration(milliseconds: 79));
    expect(
      find.byKey(const Key('reader-page-loading-1')),
      findsOneWidget,
      reason: '露出的就是这一页"还没加载好"的状态',
    );
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile(
        'goldens/reader_curl@tablet_dark_cold_under_reveal.png',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
  });
}

/// 每页一张纯色位图；被闸住的页连字节都拿不到（和真机上"还没下载下来"一致）。
class _SolidPages extends FakeReaderRepository {
  _SolidPages() : super(pageCount: 4);

  /// 与 `kFallbackPageWidth` × `kFallbackPageHeight` 同尺寸：整页正好铺满 800×1200 的视口。
  static const int _width = 1000;
  static const int _height = 1500;

  final Map<int, Uint8List> _pages = <int, Uint8List>{};

  List<PageInfo> get info => <PageInfo>[
    for (var i = 1; i <= 4; i++)
      PageInfo(
        number: i,
        width: _width,
        height: _height,
        mediaType: 'image/png',
      ),
  ];

  Future<void> prepare() async {
    const colors = <Color>[
      Color(0xFFF05046),
      Color(0xFF50C864),
      Color(0xFF5078F0),
      Color(0xFFF0BE46),
    ];
    for (var i = 0; i < colors.length; i++) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(colors[i], BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(_width, _height);
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
