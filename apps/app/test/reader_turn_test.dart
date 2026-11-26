import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/page_curl.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 翻页动画的行为：点击要带动画、横滑跟手翻页、拖得不够要回弹、墨水屏不做动画。
void main() {
  testWidgets('点击翻页也播动画：第一帧还没换页，动画结束才换', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
    );

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
    await tester.pump();

    // 动画进行中：页码还没变（纸正在卷）。
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('从右往左横滑（LTR 的下一页）：跟手拖过阈值就翻页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
    );

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('只滑一点点就松手：回弹，页码不变', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
    );

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 5'), findsOneWidget, reason: '没拖够阈值不该翻页');
  });

  testWidgets('RTL：从左往右滑才是下一页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(260, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('双页模式：横滑按"屏"翻页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 6),
      book: demoReaderBook(),
    );
    await pickMode(tester, ReaderModeChoice.double);

    await tester.drag(
      find.byKey(const Key('reader-tap-layer')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2–3 / 6'), findsOneWidget);
  });

  testWidgets('双页模式：位图就绪后走铰接卷页，翻完按屏换页（RTL）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 6),
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );
    await pickMode(tester, ReaderModeChoice.double);
    // 封面单独一屏（[0] → [1, 2] 页数不配对，走平移），先翻到 [1, 2]。
    final layer = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(layer.left + 10, layer.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2–3 / 6'), findsOneWidget);
    // 位图在空闲帧里真解码（instantiateImageCodec），要给真实的异步时间。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    await gesture.moveBy(Offset(rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '双页也要卷页，不能退化成平移');
    expect(state.debugHinged, isTrue, reason: '双页的纸铰接在书脊上');
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('4–5 / 6'), findsOneWidget);
  });

  testWidgets('单页：底层相邻页还没加载好，也照常卷页（掀开后露出它的加载态）', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 4);
    // 第 2 页（下一屏）挂住：它只决定"纸掀开之后露出什么"，不是卷页的条件。
    repository.pageGates[2] = Completer<void>();
    await pumpReader(tester, repository: repository, book: demoReaderBook());
    // 位图在空闲帧里真解码（instantiateImageCodec），要给真实的异步时间。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(Offset(-rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '当前这一页已就绪就该卷页；等底层只会换来一次没有卷页的平移');
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);
    expect(
      find.byKey(const Key('reader-page-loading-1')),
      findsOneWidget,
      reason: '纸掀开后露出的就是下一屏"还没加载好"的老实状态',
    );

    await gesture.up();
    // 翻过去的同时它到了：交接后不该再转圈。
    repository.pageGates[2]!.complete();
    // 第一个 tick 只是让控制器起表（elapsed = 0），第二个 tick 才播完。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 4'), findsOneWidget);
  });

  testWidgets('单页：当前页自己的纸面位图没好，仍然退化成平移', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 5)..failingPages.add(1);
    await pumpReader(tester, repository: repository, book: demoReaderBook());
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(Offset(-rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isFalse, reason: '纸面没有像素，卷起来只会是一块空白');
    expect(find.byKey(const Key('reader-curl-layer')), findsNothing);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('松手后从"当前已翻进度"补完，不会跳回起点重播', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 5),
      book: demoReaderBook(),
    );
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(Offset(-rect.width * 0.7, 0));
    await tester.pump();

    expect(state.debugProgress, closeTo(0.7, 0.05));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    // 关键：松手那一帧不能跳回 0（以前是 animateTo(1) 从 controller 的旧值 0 起播）。
    expect(state.debugProgress, greaterThan(0.6), reason: '补完动画必须从当前进度接着播');

    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('墨水屏：不做动画，点击一帧就换页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      forceEink: true,
    );

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
    await tester.pump();

    expect(find.text('2 / 3'), findsOneWidget, reason: '墨水屏不该有翻页动画');
  });

  testWidgets('双页模式：下一屏两页都还在加载时，往前翻照常铰接卷页', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 6);
    // 下一屏 [3, 4]（1 基第 4、5 页）全部挂住。
    repository.pageGates[4] = Completer<void>();
    repository.pageGates[5] = Completer<void>();
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
    );
    // 封面 [0] → [1, 2] 期间已经并发预解码 [1, 2]。
    final layer = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(Offset(layer.left + 10, layer.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2–3 / 6'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final gesture = await tester.startGesture(
      layer.centerLeft + const Offset(40, 0),
    );
    await gesture.moveBy(Offset(layer.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '当前屏已就绪，下一屏未加载完也应走卷页');
    expect(state.debugHinged, isTrue);
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);
    expect(find.byKey(const Key('reader-page-loading-4')), findsOneWidget);

    await gesture.up();
    repository.pageGates[4]!.complete();
    repository.pageGates[5]!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('4–5 / 6'), findsOneWidget);
  });

  testWidgets('双页模式：上一屏两页都还在加载时，往回翻照常铰接卷页', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 6);
    // 从第 4 页进入（当前屏 [3, 4]，上一屏 [1, 2] 挂住不放行）。
    repository.pageGates[2] = Completer<void>();
    repository.pageGates[3] = Completer<void>();
    await pumpReader(
      tester,
      repository: repository,
      book: Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 6,
        readProgress: ReadProgress(
          page: 4,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
    );
    expect(find.text('4–5 / 6'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(
      rect.centerRight - const Offset(40, 0),
    );
    await gesture.moveBy(Offset(-rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '双页往回翻只需当前屏落地侧就绪，不等上一屏');
    expect(state.debugHinged, isTrue);
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);
    expect(find.byKey(const Key('reader-page-loading-1')), findsOneWidget);

    await gesture.up();
    repository.pageGates[2]!.complete();
    repository.pageGates[3]!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2–3 / 6'), findsOneWidget);
  });

  testWidgets('阅读中从平移切换到卷页，不退出重进立即生效（双页）', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(pageCount: 6),
      book: Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 6,
        readProgress: ReadProgress(
          page: 2,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(
          mode: ReaderModeChoice.double,
          pageTurn: ReaderPageTurnChoice.slide,
        ),
      ),
    );
    expect(find.text('2–3 / 6'), findsOneWidget);

    // 切到卷页前，先确认此时确实是平移。
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    var gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    await gesture.moveBy(Offset(rect.width * 0.2, 0));
    await tester.pump();
    expect(state.debugCurling, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();

    // 在设置面板里从平移切换到卷页，不退出重进。
    await pickOption(tester, 'reader-turn-curl');
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    // 紧接着的第一次翻页就必须立即走卷页。
    gesture = await tester.startGesture(rect.centerLeft + const Offset(40, 0));
    await gesture.moveBy(Offset(rect.width * 0.5, 0));
    await tester.pump();
    expect(state.debugCurling, isTrue, reason: '从平移切回卷页后，第一次翻页就必须生效');
    expect(state.debugHinged, isTrue);
    expect(find.byKey(const Key('reader-curl-layer')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('4–5 / 6'), findsOneWidget);
  });

  testWidgets('双页模式：底图已在 ImageCache 显示但卷页缓存尚空时，零延迟同步借出走卷页且背面有图', (
    WidgetTester tester,
  ) async {
    final repository = FakeReaderRepository(
      pageCount: 6,
      pageNames: const <String>['p1', 'p2', 'p3'],
    );
    await pumpReader(
      tester,
      repository: repository,
      book: Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 6,
        readProgress: ReadProgress(
          page: 2,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(
          mode: ReaderModeChoice.double,
          // 先以平移模式进入：CurlSheets 完全为空，只有 ImageCache 有已解码图。
          pageTurn: ReaderPageTurnChoice.slide,
        ),
      ),
    );
    expect(find.text('2–3 / 6'), findsOneWidget);
    // 让屏幕上和预加载器的 MemoryImage 解码进 Flutter ImageCache。
    await tester.runAsync(() async {
      await PageCurlProgram.ensureLoaded();
      for (var p = 1; p <= 6; p++) {
        final bytes = await repository.pageImage('b1', p);
        final decoded = await decodeThroughImageCache(bytes);
        decoded?.dispose();
      }
    });
    await tester.pump();

    // 切到卷页后**不给任何 runAsync 异步时间**立刻起手拖动：必须同步从 ImageCache 借图卷页！
    await pickOption(tester, 'reader-turn-curl');
    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    await gesture.moveBy(Offset(rect.width * 0.5, 0));
    await tester.pump();

    expect(state.debugCurling, isTrue, reason: '底图已在 ImageCache 就绪，不得退化成平移');
    expect(state.debugHinged, isTrue);
    final curlPaint = tester.widget<CustomPaint>(
      find.byKey(const Key('reader-curl-layer')),
    );
    final painter = curlPaint.painter! as PageCurlPainter;
    expect(painter.sheet, isNotNull);
    expect(painter.back, isNotNull, reason: '下一屏已在 ImageCache 中，纸背不得是纯白');
    expect(painter.backOpacity, 1.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('4–5 / 6'), findsOneWidget);
  });

  testWidgets('双页模式：连续往后翻多屏再连续往回翻，已看过的页面全程保持铰接卷页', (WidgetTester tester) async {
    final repository = FakeReaderRepository(pageCount: 14);
    await pumpReader(
      tester,
      repository: repository,
      book: Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 14,
        readProgress: ReadProgress(
          page: 2,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
    );
    await tester.runAsync(() async {
      await PageCurlProgram.ensureLoaded();
      for (var p = 1; p <= 14; p++) {
        final bytes = await repository.pageImage('b1', p);
        final decoded = await decodeThroughImageCache(bytes);
        decoded?.dispose();
      }
    });
    await tester.pump();

    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );
    // 连续往后翻 5 屏：2–3 → 4–5 → 6–7 → 8–9 → 10–11 → 12–13。
    for (var step = 0; step < 5; step++) {
      state.turn(1);
      await tester.pump();
      expect(state.debugCurling, isTrue, reason: '第 ${step + 1} 次往前翻必须走卷页');
      expect(state.debugHinged, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('12–13 / 14'), findsOneWidget);

    // 紧接着不等待异步解码，连续往回翻 5 屏回到 2–3：每一屏都已读过，绝不能退化成平移！
    for (var step = 0; step < 5; step++) {
      state.turn(-1);
      await tester.pump();
      expect(
        state.debugCurling,
        isTrue,
        reason: '第 ${step + 1} 次往回翻已读页面必须走卷页，不能退化成平移',
      );
      expect(state.debugHinged, isTrue);
      final curlPaint = tester.widget<CustomPaint>(
        find.byKey(const Key('reader-curl-layer')),
      );
      final painter = curlPaint.painter! as PageCurlPainter;
      expect(painter.sheet, isNotNull, reason: '往回翻已读页纸面不得纯白');
      expect(painter.back, isNotNull, reason: '往回翻已读页纸背不得纯白');
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('2–3 / 14'), findsOneWidget);
  });

  testWidgets('双页模式：普通双页与跨页宽图（wide spread）往返翻页均保持书脊铰接卷页', (
    WidgetTester tester,
  ) async {
    // 页序：0=封面(单), [1,2]=普通双页, [3]=宽页跨页大图(1600×1200), [4,5]=普通双页。
    final repository = FakeReaderRepository(
      pageCount: 6,
      pageSizes: const <({int width, int height})>[
        (width: 800, height: 1200),
        (width: 800, height: 1200),
        (width: 800, height: 1200),
        (width: 1600, height: 1200),
        (width: 800, height: 1200),
        (width: 800, height: 1200),
      ],
    );
    await pumpReader(
      tester,
      repository: repository,
      book: Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 6,
        readProgress: ReadProgress(
          page: 2,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
    );
    await tester.runAsync(() async {
      await PageCurlProgram.ensureLoaded();
      for (var p = 1; p <= 6; p++) {
        final bytes = await repository.pageImage('b1', p);
        final decoded = await decodeThroughImageCache(bytes);
        decoded?.dispose();
      }
    });
    await tester.pump();
    expect(find.text('2–3 / 6'), findsOneWidget);

    final state = tester.state<ReaderPagedViewState>(
      find.byType(ReaderPagedView),
    );

    // 1. 普通双页 [1,2] → 宽页 [3]：铰接卷页
    state.turn(1);
    await tester.pump();
    expect(state.debugCurling, isTrue, reason: '双页翻向宽页跨页图不应退化成平移');
    expect(state.debugHinged, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('4 / 6'), findsOneWidget);

    // 2. 宽页 [3] → 普通双页 [4,5]：铰接卷页
    state.turn(1);
    await tester.pump();
    expect(state.debugCurling, isTrue, reason: '宽页跨页图翻向双页不应退化成平移');
    expect(state.debugHinged, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('5–6 / 6'), findsOneWidget);

    // 3. 普通双页 [4,5] 往回翻 → 宽页 [3]：铰接卷页
    state.turn(-1);
    await tester.pump();
    expect(state.debugCurling, isTrue, reason: '从双页往回翻向宽页不应退化成平移');
    expect(state.debugHinged, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('4 / 6'), findsOneWidget);

    // 4. 宽页 [3] 往回翻 → 普通双页 [1,2]：铰接卷页
    state.turn(-1);
    await tester.pump();
    expect(state.debugCurling, isTrue, reason: '从宽页往回翻向双页不应退化成平移');
    expect(state.debugHinged, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2–3 / 6'), findsOneWidget);
  });

  testWidgets('双页模式：冷页纸背在深色背景下不用刺眼纯白，且途中下载完平滑淡入不突变', (
    WidgetTester tester,
  ) async {
    // 用 3 张不同页图名，避免第 4 页循环复用第 1 页字节。
    final repository = FakeReaderRepository(
      pageCount: 6,
      pageNames: const <String>['p1', 'p2', 'p3'],
    );
    // 闸住第 4、5 页（下一屏 [3, 4]）。
    repository.pageGates[4] = Completer<void>();
    repository.pageGates[5] = Completer<void>();
    await pumpReader(
      tester,
      repository: repository,
      book: Book(
        id: 'b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 6,
        readProgress: ReadProgress(
          page: 2,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ),
      direction: ReadingDirection.rightToLeft,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.double),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    await gesture.moveBy(Offset(rect.width * 0.45, 0));
    await tester.pump();

    var painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('reader-curl-layer')))
                .painter!
            as PageCurlPainter;
    expect(painter.back, isNull);
    expect(painter.paperColor, isNotNull);
    expect(
      painter.paperColor!.computeLuminance(),
      lessThan(0.1),
      reason: '深色模式下未就绪纸背用哑光深灰，不能闪纯白',
    );

    // 手指还按在半空中时，下一屏下载并解码完成：纸背应在卷动途中平滑淡入（0 → 1）。
    repository.pageGates[4]!.complete();
    repository.pageGates[5]!.complete();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('reader-curl-layer')))
                .painter!
            as PageCurlPainter;
    expect(painter.back, isNotNull, reason: '翻动期间后台解码不中断，纸背途中即可就绪');
    expect(painter.backOpacity, greaterThan(0.0));

    await tester.pump(const Duration(milliseconds: 200));
    painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('reader-curl-layer')))
                .painter!
            as PageCurlPainter;
    expect(painter.backOpacity, 1.0, reason: '淡入动画完成后纸背达到完全不透明，落地无突变');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('4–5 / 6'), findsOneWidget);
  });
}
