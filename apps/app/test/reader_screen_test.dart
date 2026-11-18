import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/fakes.dart';
import 'support/reader_harness.dart';

/// 阅读器的基础行为：打开/翻页/进度/失败态，以及三种模式的渲染。
/// 设置面板（模式持久化、亮度、常亮、跳页）在 `reader_settings_test.dart`。
void main() {
  testWidgets('打开即显示第一页与页码', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(repository.pageImageCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('离线时顶栏出现缓存提示（阅读区不挤占）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), offline: true);

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('有进度时从上次那一页继续', (WidgetTester tester) async {
    final book = Book(
      id: 'b1',
      seriesId: 's1',
      name: 'Vol. 1',
      number: '1',
      pagesCount: 3,
      readProgress: ReadProgress(
        page: 2,
        completed: false,
        lastModified: DateTime.utc(2026, 1, 1),
      ),
    );
    await pumpReader(tester, book: book);

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('点右侧翻页，并在防抖后把进度写回服务端', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);

    // 防抖 600ms 内不应写；等过去之后写一次第 2 页。
    expect(repository.saved, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));
    expect(repository.saved, <({int page, bool completed})>[
      (page: 2, completed: false),
    ]);
  });

  testWidgets('翻到最后一页时 completed 置真', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    await tapRight(tester);
    await tapRight(tester);
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(repository.saved.last, (page: 3, completed: true));
  });

  testWidgets('右到左的书：点左侧才是下一页', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
    );

    await tapLeft(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('点中间隐藏/显示顶栏与底栏', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    expect(find.byTooltip('Close'), findsOneWidget);

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);

    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('页列表加载失败 → 错误页 + 重试', (WidgetTester tester) async {
    final repository = FakeReaderRepository(
      pagesFailure: const NetworkFailure(),
    );
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    expect(find.text('Cannot reach the server'), findsOneWidget);

    repository.pagesFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('单页图加载失败 → 页内提示 + 重试', (WidgetTester tester) async {
    final repository = FakeReaderRepository(
      imageFailure: const ServerFailure(),
    );
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    expect(find.text('Server error'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget, reason: '页码仍应可用');

    repository.imageFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('进度回写失败不影响继续阅读', (WidgetTester tester) async {
    final repository = FakeReaderRepository(
      saveFailure: const NetworkFailure(),
    );
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('2 / 3'), findsOneWidget);
  });

  group('音量键翻页', () {
    testWidgets('音量下下一页、音量上上一页（单页）', (WidgetTester tester) async {
      final keys = FakeHardwareKeys();
      await pumpReader(tester, book: demoReaderBook(), hardwareKeys: keys);
      expect(find.text('1 / 3'), findsOneWidget);

      keys.emit(PageTurnKey.next);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      keys.emit(PageTurnKey.previous);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      await keys.close();
    });

    testWidgets('双页模式按屏翻页', (WidgetTester tester) async {
      final keys = FakeHardwareKeys();
      await pumpReader(tester, book: demoReaderBook(), hardwareKeys: keys);
      await pickMode(tester, ReaderModeChoice.double);
      expect(find.text('1 / 3'), findsOneWidget);

      keys.emit(PageTurnKey.next);
      await tester.pumpAndSettle();
      expect(find.text('2–3 / 3'), findsOneWidget);

      keys.emit(PageTurnKey.previous);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      await keys.close();
    });

    testWidgets('纵向连续模式忽略音量键（滚动优先）', (WidgetTester tester) async {
      final keys = FakeHardwareKeys();
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.vertical,
        hardwareKeys: keys,
      );
      expect(find.byKey(const Key('reader-vertical-list')), findsOneWidget);

      keys.emit(PageTurnKey.next);
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
      await keys.close();
    });
  });

  group('双页跨页', () {
    testWidgets('封面单独一屏，后两页并成一屏', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      await pickMode(tester, ReaderModeChoice.double);

      // 第 1 屏只有封面。
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      await tapRight(tester);
      expect(find.text('2–3 / 3'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('右到左时后一页画在左边', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.rightToLeft,
      );
      await pickMode(tester, ReaderModeChoice.double);
      // RTL：点左侧才是"下一页"。
      await tapLeft(tester);
      expect(find.text('2–3 / 3'), findsOneWidget);

      final page2 = tester.getTopLeft(find.byKey(const Key('reader-image-1')));
      final page3 = tester.getTopLeft(find.byKey(const Key('reader-image-2')));
      expect(page3.dx, lessThan(page2.dx), reason: '日漫后一页应在左');
    });

    testWidgets('宽页（跨页大图）单独占一屏，不和相邻页挤在一起', (WidgetTester tester) async {
      final repository = FakeReaderRepository(
        pageSizes: <({int width, int height})>[
          (width: 800, height: 1200),
          (width: 1600, height: 1000), // 宽页
          (width: 800, height: 1200),
        ],
      );
      await pumpReader(tester, repository: repository, book: demoReaderBook());
      await pickMode(tester, ReaderModeChoice.double);

      await tapRight(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('切模式不丢页码：单页第 2 页 ↔ 双页 2–3', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      await tapRight(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await pickMode(tester, ReaderModeChoice.double);
      expect(find.text('2–3 / 3'), findsOneWidget);

      await pickMode(tester, ReaderModeChoice.single);
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('最后一屏包含末页时也要标 completed', (WidgetTester tester) async {
      final repository = FakeReaderRepository();
      await pumpReader(tester, repository: repository, book: demoReaderBook());
      await pickMode(tester, ReaderModeChoice.double);
      await tapRight(tester);
      expect(find.text('2–3 / 3'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      // 页码停在 2（这一屏的起始页），但已到末尾，completed 必须为真；
      // 否则系列进度会永远差一页。
      expect(repository.saved.last, (page: 2, completed: true));
    });
  });

  group('纵向连续', () {
    testWidgets('条漫方向默认进纵向连续', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.webtoon,
      );

      expect(find.byKey(const Key('reader-vertical-list')), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('滚动后页码跟随，并把进度写回服务端', (WidgetTester tester) async {
      final repository = FakeReaderRepository();
      await pumpReader(
        tester,
        repository: repository,
        book: demoReaderBook(),
        direction: ReadingDirection.vertical,
      );

      await tester.drag(
        find.byKey(const Key('reader-vertical-list')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 / 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(repository.saved.last.page, 2);
    });

    testWidgets('纵向模式底栏按钮不可用（只靠滚动）', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.vertical,
      );

      final prev = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(prev.onPressed, isNull);
    });
  });

  group('底栏页码与翻页箭头', () {
    testWidgets('底栏显示当前页码，翻页后跟着变（不是总页数）', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('3 pages'), findsNothing, reason: '底栏不该再显示总页数');

      await tapRight(tester);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 1'), findsNothing);
    });

    testWidgets('双页模式底栏显示当前跨页', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());
      await pickMode(tester, ReaderModeChoice.double);

      await tapRight(tester);
      expect(find.text('Pages 2–3'), findsOneWidget);
    });

    testWidgets('LTR：左侧是上一页，右侧是下一页（与点击区一致）', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook());

      final previous = tester.getCenter(
        find.byKey(const Key('reader-previous-button')),
      );
      final next = tester.getCenter(
        find.byKey(const Key('reader-next-button')),
      );
      expect(previous.dx, lessThan(next.dx));

      await tester.tap(find.byKey(const Key('reader-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader-previous-button')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('RTL：左侧按钮变成下一页（和左侧点击区同一个方向）', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.rightToLeft,
      );

      final previous = tester.getCenter(
        find.byKey(const Key('reader-previous-button')),
      );
      final next = tester.getCenter(
        find.byKey(const Key('reader-next-button')),
      );
      expect(next.dx, lessThan(previous.dx), reason: '日漫下一页在左');

      // 点左侧的"下一页"按钮 → 前进；再点右侧的"上一页"按钮 → 回来。
      await tester.tap(find.byKey(const Key('reader-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader-previous-button')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });
  });

  group('页图预加载', () {
    testWidgets('打开第一页就把下一屏取好了（不是翻页时才现取）', (WidgetTester tester) async {
      final repository = FakeReaderRepository(pageCount: 5);
      await pumpReader(tester, repository: repository, book: demoReaderBook());

      // 屏幕上只有第 1 页，但 2、3 已经取过；否则第一次翻页要等网络，
      // 那段空档就是用户看到的"闪一下黑"。
      expect(repository.pageRequests, containsAll(<int>[2, 3]));
      expect(
        repository.pageRequests,
        isNot(contains(5)),
        reason: '只预热前后一屏，不该把整本都拖下来',
      );
    });

    testWidgets('翻页后预取跟着走：新位置的前后一屏都取', (WidgetTester tester) async {
      final repository = FakeReaderRepository(pageCount: 5);
      await pumpReader(tester, repository: repository, book: demoReaderBook());

      await tapRight(tester);
      expect(find.text('2 / 5'), findsOneWidget);
      // 第 2 页的下一屏是 3、4，上一屏是 1。
      expect(repository.pageRequests, containsAll(<int>[3, 4]));
    });

    testWidgets('双页模式按"屏"预取：下一屏的第二页也不能漏', (WidgetTester tester) async {
      final repository = FakeReaderRepository(pageCount: 6);
      await pumpReader(tester, repository: repository, book: demoReaderBook());
      await pickMode(tester, ReaderModeChoice.double);

      // 第 1 屏只有封面，翻到第 2 屏（2–3）。
      await tapRight(tester);
      expect(find.text('2–3 / 6'), findsOneWidget);
      // 下一屏是 4–5。只按 `page + 1` 算的话第 5 页永远轮不到预热，
      // 结果就是"翻一屏有一页是空的"（每两屏闪一次）。
      expect(repository.pageRequests, containsAll(<int>[4, 5]));
    });

    testWidgets('紧接着的那一屏会被解码进 ImageCache（翻页首帧就有像素）', (
      WidgetTester tester,
    ) async {
      final repository = FakeReaderRepository();
      await pumpReader(tester, repository: repository, book: demoReaderBook());

      final next = await repository.warmPage(2);
      // 测试的假时钟推不动真实解码，必须放一段真实时间。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

      expect(next, isNotNull);
      expect(
        PaintingBinding.instance.imageCache.containsKey(MemoryImage(next!)),
        isTrue,
        reason: '只抓字节不预解码的话，翻过去第一帧是空白（黑屏）',
      );
    });
  });

  group('翻页首帧（不能先闪一帧 loading）', () {
    testWidgets('翻到已预取的下一页：第一帧就有图', (WidgetTester tester) async {
      await pumpReader(
        tester,
        repository: FakeReaderRepository(pageCount: 5),
        book: demoReaderBook(),
      );

      await tapRightOneFrame(tester);

      // `pumpAndSettle` 会把中间那一帧 loading 吞掉，所以这里只推进一帧：
      // 用户看到的就是这一帧（黑底 + 转圈 = "闪一下"）。
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('reader-image-1')), findsOneWidget);
    });

    testWidgets('翻回已经读过的页：第一帧就有图', (WidgetTester tester) async {
      await pumpReader(
        tester,
        repository: FakeReaderRepository(pageCount: 5),
        book: demoReaderBook(),
      );
      await tapRight(tester);

      await tapLeftOneFrame(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    });
  });

  group('墨水屏', () {
    testWidgets('阅读区改白底黑字（黑底会触发整屏全刷）', (WidgetTester tester) async {
      await pumpReader(tester, book: demoReaderBook(), forceEink: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppTheme.einkPaper);

      final title = tester.widget<Text>(find.text('Vol. 1'));
      expect(title.style?.color, AppTheme.einkInk);
    });

    testWidgets('墨水屏纵向模式同样是白底', (WidgetTester tester) async {
      await pumpReader(
        tester,
        book: demoReaderBook(),
        direction: ReadingDirection.webtoon,
        forceEink: true,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppTheme.einkPaper);
      expect(find.byKey(const Key('reader-vertical-list')), findsOneWidget);
    });
  });
}
