import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu/src/widgets/reader_progress_writer.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 竖版页（宽 < 高），双页模式会两两配对。
List<PageInfo> portrait(int count) => <PageInfo>[
  for (var i = 1; i <= count; i++)
    PageInfo(number: i, width: 1000, height: 1500),
];

void main() {
  group('ReaderLayout', () {
    test('单页：首末页翻页边界', () {
      final first = ReaderLayout(
        pages: portrait(3),
        mode: ReadingMode.paged,
        page: 1,
      );
      expect(first.canGoBack, isFalse);
      expect(first.canGoForward, isTrue);
      expect(first.turnTarget(-1), isNull);
      expect(first.turnTarget(1), 2);
      expect(first.neighbour(-1), isNull);
      expect(first.neighbour(1), <int>[1]);
      expect(first.spread, <int>[0]);

      final last = ReaderLayout(
        pages: portrait(3),
        mode: ReadingMode.paged,
        page: 3,
      );
      expect(last.canGoForward, isFalse);
      expect(last.turnTarget(1), isNull);
      expect(last.completed, isTrue);
    });

    test('双页：封面单独、其余两两；最后一屏含末页即算读完', () {
      // 5 页：[0] [1,2] [3,4]
      final layout = ReaderLayout(
        pages: portrait(5),
        mode: ReadingMode.doublePage,
        page: 4,
      );
      expect(layout.spreads, <List<int>>[
        <int>[0],
        <int>[1, 2],
        <int>[3, 4],
      ]);
      expect(layout.spread, <int>[3, 4]);
      // page 4 ≠ total 5，但这一屏已含末页。
      expect(layout.completed, isTrue);
      expect(layout.canGoForward, isFalse);
      expect(layout.turnTarget(-1), 2);
      expect(layout.neighbour(-1), <int>[1, 2]);
      expect(layout.isCompletedAt(2), isFalse);
    });

    test('纵向：不走翻页', () {
      final layout = ReaderLayout(
        pages: portrait(3),
        mode: ReadingMode.verticalScroll,
        page: 2,
      );
      expect(layout.spreads, isEmpty);
      expect(layout.canGoBack, isFalse);
      expect(layout.canGoForward, isFalse);
      expect(layout.turnTarget(1), isNull);
    });

    test('只有一页：单页与双页都直接读完、两边都翻不动', () {
      for (final mode in <ReadingMode>[
        ReadingMode.paged,
        ReadingMode.doublePage,
      ]) {
        final layout = ReaderLayout(pages: portrait(1), mode: mode, page: 1);
        expect(layout.completed, isTrue, reason: mode.name);
        expect(layout.canGoBack, isFalse, reason: mode.name);
        expect(layout.canGoForward, isFalse, reason: mode.name);
      }
    });
  });

  group('ReaderProgressWriter', () {
    testWidgets('连续翻页只写最后停下的那一页', (WidgetTester tester) async {
      final written = <int>[];
      final writer = ReaderProgressWriter(
        write: (int page) async => written.add(page),
      );
      writer
        ..schedule(2)
        ..schedule(3)
        ..schedule(4);
      await tester.pump(ReaderProgressWriter.defaultDelay);
      expect(written, <int>[4]);
    });

    testWidgets('flush 立刻写、取消待写；同一页不重复写', (WidgetTester tester) async {
      final written = <int>[];
      final writer = ReaderProgressWriter(
        write: (int page) async => written.add(page),
      );
      writer.schedule(5);
      await writer.flush(5);
      await tester.pump(ReaderProgressWriter.defaultDelay);
      await writer.flush(5);
      expect(written, <int>[5]);
    });

    testWidgets('写失败不抛出，下次同一页会重试', (WidgetTester tester) async {
      var attempts = 0;
      final writer = ReaderProgressWriter(
        write: (int page) async {
          attempts++;
          if (attempts == 1) throw StateError('disk full');
        },
      );
      await writer.flush(7);
      await writer.flush(7);
      expect(attempts, 2);
    });

    testWidgets('dispose 后待写的不再执行', (WidgetTester tester) async {
      final written = <int>[];
      final writer = ReaderProgressWriter(
        write: (int page) async => written.add(page),
      );
      writer
        ..schedule(9)
        ..dispose();
      await tester.pump(ReaderProgressWriter.defaultDelay * 2);
      expect(written, isEmpty);
    });
  });
}
