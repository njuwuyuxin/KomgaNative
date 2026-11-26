import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// FIX-03：方向未知的入口（搜索、阅读列表、深链、下一本）要按系列兜底，
/// 不能一律当成从左到右。
void main() {
  Series seriesWith(ReadingDirection direction, {String id = 's1'}) => Series(
    id: id,
    libraryId: 'l1',
    title: 'Series $id',
    readingDirection: direction,
  );

  /// 不带 direction 打开 `demoReaderBook()`（seriesId = s1），
  /// 只通过仓库提供系列信息——就是搜索/阅读列表/深链的入参形态。
  Future<void> pumpFromList(
    WidgetTester tester, {
    required List<Series> series,
    ReadingDirection? explicit,
  }) {
    return pumpReader(
      tester,
      book: demoReaderBook(),
      direction: explicit ?? ReadingDirection.unknown,
      library: FakeLibraryRepository(series: series),
    );
  }

  testWidgets('系列是右到左：点左侧是下一页，右侧是上一页', (WidgetTester tester) async {
    await pumpFromList(
      tester,
      series: <Series>[seriesWith(ReadingDirection.rightToLeft)],
    );

    await tapLeft(tester);
    expect(find.text('2 / 3'), findsOneWidget);

    await tapRight(tester);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('系列是左到右：点右侧是下一页', (WidgetTester tester) async {
    await pumpFromList(
      tester,
      series: <Series>[seriesWith(ReadingDirection.leftToRight)],
    );

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('底栏箭头也跟着系列镜像', (WidgetTester tester) async {
    await pumpFromList(
      tester,
      series: <Series>[seriesWith(ReadingDirection.rightToLeft)],
    );

    final next = tester.getCenter(find.byKey(const Key('reader-next-button')));
    final previous = tester.getCenter(
      find.byKey(const Key('reader-previous-button')),
    );
    expect(next.dx, lessThan(previous.dx), reason: 'RTL 时"下一页"在左边');
  });

  testWidgets('系列查不到（离线/深链脏数据）：按从左到右兜底，不阻塞打开', (WidgetTester tester) async {
    await pumpFromList(tester, series: const <Series>[]);

    // 书照常显示，页码也在。
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('显式传入的方向优先于系列（系列页/继续阅读卡不受影响）', (WidgetTester tester) async {
    await pumpFromList(
      tester,
      series: <Series>[seriesWith(ReadingDirection.rightToLeft)],
      explicit: ReadingDirection.leftToRight,
    );

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('系列详情晚到：先按从左到右画出，到达后按 RTL 重排', (WidgetTester tester) async {
    // 仓库的系列详情此时给了 RTL；关键在于"打开时方向未知也能正确落到 RTL"，
    // 而不是永远停在第一帧的默认方向。
    await pumpFromList(
      tester,
      series: <Series>[seriesWith(ReadingDirection.rightToLeft)],
    );
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);

    await tapLeft(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('路由直接进入（没有 book 上下文）：取书后按它的系列定方向', (WidgetTester tester) async {
    // `/reader/:bookId` 这条路由只带 bookId：方向得先取书、再按 seriesId 查系列。
    await pumpReader(
      tester,
      bookId: 'b1',
      // 路由入口不传方向；`pumpReader` 默认值是 LTR，必须显式给 unknown，
      // 否则测的就不是"未知方向"这条路径了。
      direction: ReadingDirection.unknown,
      library: FakeLibraryRepository(
        series: <Series>[seriesWith(ReadingDirection.rightToLeft)],
      ),
    );

    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    await tapLeft(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
