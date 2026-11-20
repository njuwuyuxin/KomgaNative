import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/page_save.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/fakes.dart';
import 'support/reader_harness.dart';

/// 阅读界面"保存图片"按钮：单页直接保存原图，双页按屏幕左右视觉顺序无缝拼接后保存。
void main() {
  Future<Uint8List> makeSolidPng(
    WidgetTester tester, {
    required int width,
    required int height,
    required Color color,
  }) async {
    return (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..color = color,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }))!;
  }

  Future<({int width, int height, Color leftSample, Color rightSample})>
  inspectPng(WidgetTester tester, Uint8List bytes) async {
    return (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final w = image.width;
      final h = image.height;
      image.dispose();
      codec.dispose();

      Color pixelAt(int x, int y) {
        final offset = (y * w + x) * 4;
        return Color.fromARGB(
          rgba.getUint8(offset + 3),
          rgba.getUint8(offset),
          rgba.getUint8(offset + 1),
          rgba.getUint8(offset + 2),
        );
      }

      return (
        width: w,
        height: h,
        leftSample: pixelAt(w ~/ 4, h ~/ 2),
        rightSample: pixelAt((w * 3) ~/ 4, h ~/ 2),
      );
    }))!;
  }

  testWidgets('单页模式：点击保存按钮直接保存当前单张图片并弹出提示', (WidgetTester tester) async {
    final saver = FakeImageSaver();
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      imageSaver: saver,
    );

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);

    final expectedPage2 = await repository.pageImage('b1', 2);
    await tester.tap(find.byKey(const Key('reader-save-image-button')));
    await tester.pumpAndSettle();

    expect(saver.saved, hasLength(1));
    expect(saver.saved.single.fileName, 'komganative-b1-page-2.png');
    expect(saver.saved.single.mimeType, 'image/png');
    expect(saver.saved.single.bytes, expectedPage2);
    expect(find.text('Image saved'), findsOneWidget);
  });

  testWidgets('纵向连续模式：点击保存按钮保存当前所在页', (WidgetTester tester) async {
    final saver = FakeImageSaver();
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      direction: ReadingDirection.webtoon,
      imageSaver: saver,
    );

    await tester.tap(find.byKey(const Key('reader-save-image-button')));
    await tester.pumpAndSettle();

    expect(saver.saved, hasLength(1));
    expect(saver.saved.single.fileName, 'komganative-b1-page-1.png');
  });

  testWidgets('双页模式（封面单独成屏）：只保存封面单张图片，不拼接', (WidgetTester tester) async {
    final saver = FakeImageSaver();
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
      imageSaver: saver,
    );

    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-save-image-button')));
    await tester.pumpAndSettle();

    expect(saver.saved, hasLength(1));
    expect(saver.saved.single.fileName, 'komganative-b1-page-1.png');
    expect(saver.saved.single.bytes, await repository.pageImage('b1', 1));
  });

  testWidgets('双页模式 LTR 与 RTL：按屏幕左右顺序自动拼接两幅图为一幅完整大图', (
    WidgetTester tester,
  ) async {
    const colorP1 = Color(0xFF202020);
    const colorP2 = Color(0xFFE03040); // 第 2 页：红
    const colorP3 = Color(0xFF2070E0); // 第 3 页：蓝
    final p1 = await makeSolidPng(
      tester,
      width: 40,
      height: 60,
      color: colorP1,
    );
    final p2 = await makeSolidPng(
      tester,
      width: 40,
      height: 60,
      color: colorP2,
    );
    final p3 = await makeSolidPng(
      tester,
      width: 50,
      height: 60,
      color: colorP3,
    );
    final repository = _MemoryPageReaderRepository(<Uint8List>[p1, p2, p3]);
    final saver = FakeImageSaver();

    // 1) LTR：第 2–3 页左红（p2）右蓝（p3）。
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      direction: ReadingDirection.leftToRight,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
      imageSaver: saver,
    );
    await tapRight(tester);
    expect(find.text('2–3 / 3'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('reader-save-image-button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(saver.saved, hasLength(1));
    expect(saver.saved.single.fileName, 'komganative-b1-pages-2-3.png');
    expect(saver.saved.single.mimeType, 'image/png');
    final ltrInfo = await inspectPng(tester, saver.saved.single.bytes);
    expect(ltrInfo.width, 90);
    expect(ltrInfo.height, 60);
    expect(ltrInfo.leftSample, colorP2);
    expect(ltrInfo.rightSample, colorP3);

    // 2) 切到 RTL（日漫）：屏幕上第 3 页在左、第 2 页在右，拼接结果也必须左蓝（p3）右红（p2）。
    saver.saved.clear();
    await openQuickSettings(tester);
    final rtlPill = find.byKey(const Key('quick-direction-rightToLeft'));
    await tester.ensureVisible(rtlPill);
    await tester.pumpAndSettle();
    await tester.tap(rtlPill);
    await tester.pumpAndSettle();
    await closeSheet(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('reader-save-image-button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(saver.saved, hasLength(1));
    expect(saver.saved.single.fileName, 'komganative-b1-pages-2-3.png');
    final rtlInfo = await inspectPng(tester, saver.saved.single.bytes);
    expect(rtlInfo.width, 90);
    expect(rtlInfo.height, 60);
    expect(rtlInfo.leftSample, colorP3, reason: 'RTL 日漫后一页在左，拼接大图左侧应是第 3 页');
    expect(rtlInfo.rightSample, colorP2, reason: 'RTL 日漫前一页在右，拼接大图右侧应是第 2 页');
  });

  testWidgets('双页模式高度不同时等比对齐到较高侧，无缝输出完整大图', (WidgetTester tester) async {
    final left = await makeSolidPng(
      tester,
      width: 20,
      height: 30,
      color: const Color(0xFF30A050),
    );
    final right = await makeSolidPng(
      tester,
      width: 40,
      height: 60,
      color: const Color(0xFFD08020),
    );

    final stitched = (await tester.runAsync(
      () => stitchSideBySidePng(left, right),
    ))!;
    final info = await inspectPng(tester, stitched);
    expect(info.width, 80);
    expect(info.height, 60);
    expect(info.leftSample, const Color(0xFF30A050));
    expect(info.rightSample, const Color(0xFFD08020));
  });

  testWidgets('保存失败（网络取图失败 / 权限拒绝 / I/O 错误）弹提示且不打断阅读', (
    WidgetTester tester,
  ) async {
    final saver = FakeImageSaver(
      nextResult: const ImageSaveFailure(ImageSaveFailureKind.permissionDenied),
    );
    final repository = FakeReaderRepository();
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      imageSaver: saver,
    );

    await tester.tap(find.byKey(const Key('reader-save-image-button')));
    await tester.pumpAndSettle();
    expect(find.text('Storage permission denied'), findsOneWidget);

    saver.nextResult = const ImageSaveFailure(ImageSaveFailureKind.ioError);
    await tester.tap(find.byKey(const Key('reader-save-image-button')));
    await tester.pumpAndSettle();
    expect(find.text('Could not save this image'), findsOneWidget);

    repository.imageFailure = const NetworkFailure();
    await tester.tap(find.byKey(const Key('reader-save-image-button')));
    await tester.pumpAndSettle();
    expect(find.text('Cannot reach the server'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });
}

class _MemoryPageReaderRepository extends FakeReaderRepository {
  _MemoryPageReaderRepository(this._customPages)
    : super(
        pageCount: _customPages.length,
        pageSizes: const <({int width, int height})>[
          (width: 400, height: 600),
          (width: 400, height: 600),
          (width: 500, height: 600),
        ],
      );

  final List<Uint8List> _customPages;

  @override
  Future<Uint8List> pageImage(String bookId, int page) async {
    pageImageCalls++;
    pageRequests.add(page);
    final failure = imageFailure;
    if (failure != null) throw failure;
    return _customPages[(page - 1) % _customPages.length];
  }

  @override
  Uint8List? cachedPageImage(String bookId, int page) =>
      _customPages[(page - 1) % _customPages.length];
}
