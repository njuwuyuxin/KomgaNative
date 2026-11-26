import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/widgets/page_navigator_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 缩略图跳页面板：打开、点选、取消、加载失败时的容错。
void main() {
  testWidgets('顶栏 Pages 按钮打开缩略图网格', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await openPages(tester);

    expect(find.byType(PageNavigatorSheet), findsOneWidget);
    expect(find.byKey(const Key('page-navigator-grid')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-3')), findsOneWidget);
  });

  testWidgets('点缩略图跳到对应页', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await openPages(tester);
    await tester.tap(find.byKey(const Key('page-thumb-3')));
    await tester.pumpAndSettle();

    expect(find.byType(PageNavigatorSheet), findsNothing);
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('关掉面板不改变页码', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await openPages(tester);
    await tester.tap(find.byKey(const Key('page-navigator-close')));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('缩略图加载失败只画占位，面板照常可用', (WidgetTester tester) async {
    // 只让第 2、3 页失败：第 1 页（正在读的那页）照常，缩略图和面板里那两页退化成占位。
    // 失败必须在首帧之前定好——底栏滑条一上来就会把可见页的字节请回来。
    final repository = FakeReaderRepository()..failingPages.addAll(<int>[2, 3]);
    await pumpReader(tester, repository: repository, book: demoReaderBook());

    await openPages(tester);

    expect(find.byType(PageNavigatorSheet), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsWidgets);
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
  });
}
