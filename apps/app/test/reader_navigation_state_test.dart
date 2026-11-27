import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/features/reader/reader_navigation_state.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

void main() {
  group('P3-1 ReaderNavigationState & resolveReaderKeyAction', () {
    final pages = <PageInfo>[
      const PageInfo(
        number: 1,
        mediaType: 'image/png',
        width: 800,
        height: 1200,
      ),
      const PageInfo(
        number: 2,
        mediaType: 'image/png',
        width: 2000,
        height: 1000,
      ),
      const PageInfo(
        number: 3,
        mediaType: 'image/png',
        width: 800,
        height: 1200,
      ),
    ];

    test('页码恢复、钳制与 0 页边界', () {
      final nav = ReaderNavigationState();
      expect(nav.resolvePage(total: 0, resumedPage: 5), 1);
      expect(nav.resolvePage(total: 3, resumedPage: null), 1);
      expect(nav.resolvePage(total: 3, resumedPage: 99), 3);
      expect(nav.resolvePage(total: 3, resumedPage: 2), 2);

      final jumped = nav.jumpTo(99, 3);
      expect(jumped, 3);
      expect(nav.page, 3);
      expect(nav.jumpPage, 3);
      expect(nav.jumpToken, 1);
    });

    test('宽页自动切分半幅翻页与临时合页翻离自动清空', () {
      final nav = ReaderNavigationState()
        ..direction = ReadingDirection.rightToLeft
        ..setPage(2);
      const config = ReaderConfig(
        mode: ReaderModeChoice.single,
        splitWidePages: WidePageSplitMode.autoPortrait,
      );

      final splitLayout = nav.buildLayout(
        pages: pages,
        tabletLayout: TabletLayoutChoice.auto,
        config: config,
        resumedPage: 1,
        groupFrom: null,
      );
      expect(splitLayout.isWideSplitActive, isTrue);

      // 在宽页第一半幅向前翻页应先切到另一半幅，页码保持 2。
      final halfTurn = nav.handlePagedTurn(
        layout: splitLayout,
        delta: 1,
        hasNextBook: true,
      );
      expect(halfTurn, isA<ReaderTurnMoved>());
      expect((halfTurn as ReaderTurnMoved).page, 2);
      expect(halfTurn.half, isNotNull);

      // 临时合页开关切换并在翻离物理页时自动清空。
      nav.toggleTempMerge(1);
      expect(nav.mergedWidePageIndex, 1);
      expect(nav.pageHalf, isNull);
      nav.setPage(3);
      expect(nav.mergedWidePageIndex, isNull);
    });

    test('末页继续向后翻页在存在下一本时触发 ReaderTurnOpenNextBook', () {
      final nav = ReaderNavigationState()..setPage(3);
      const config = ReaderConfig(mode: ReaderModeChoice.single);
      final layout = nav.buildLayout(
        pages: pages,
        tabletLayout: TabletLayoutChoice.auto,
        config: config,
        resumedPage: 1,
        groupFrom: null,
      );

      expect(
        nav.handlePagedTurn(layout: layout, delta: 1, hasNextBook: true),
        isA<ReaderTurnOpenNextBook>(),
      );
      expect(
        nav.handlePagedTurn(layout: layout, delta: 1, hasNextBook: false),
        isA<ReaderTurnNone>(),
      );
    });

    test('resolveReaderKeyAction 按 LTR/RTL 映射方向键、翻页键与 Escape，忽略 KeyUp', () {
      KeyDownEvent down(LogicalKeyboardKey k) => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: k,
        timeStamp: Duration.zero,
      );

      final ltrRight = resolveReaderKeyAction(
        down(LogicalKeyboardKey.arrowRight),
        rightToLeft: false,
      );
      expect((ltrRight! as ReaderTurnAction).delta, 1);

      final rtlRight = resolveReaderKeyAction(
        down(LogicalKeyboardKey.arrowRight),
        rightToLeft: true,
      );
      expect((rtlRight! as ReaderTurnAction).delta, -1);

      final rtlLeft = resolveReaderKeyAction(
        down(LogicalKeyboardKey.arrowLeft),
        rightToLeft: true,
      );
      expect((rtlLeft! as ReaderTurnAction).delta, 1);

      expect(
        (resolveReaderKeyAction(
                  down(LogicalKeyboardKey.space),
                  rightToLeft: true,
                )!
                as ReaderTurnAction)
            .delta,
        1,
      );
      expect(
        (resolveReaderKeyAction(
                  down(LogicalKeyboardKey.pageUp),
                  rightToLeft: false,
                )!
                as ReaderTurnAction)
            .delta,
        -1,
      );
      expect(
        resolveReaderKeyAction(
          down(LogicalKeyboardKey.escape),
          rightToLeft: false,
        ),
        isA<ReaderExitAction>(),
      );
      expect(
        resolveReaderKeyAction(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.arrowRight,
            logicalKey: LogicalKeyboardKey.arrowRight,
            timeStamp: Duration.zero,
          ),
          rightToLeft: false,
        ),
        isNull,
      );
    });
  });
}
