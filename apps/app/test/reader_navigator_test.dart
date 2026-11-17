import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/widgets/page_navigator_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 缩略图跳页面板：打开、点选、取消、加载失败时的容错。
void main() {
  testWidgets('顶栏 Pages 按钮打开缩略图网格', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await tester.tap(find.byKey(const Key('reader-pages-button')));
    await tester.pumpAndSettle();

    expect(find.byType(PageNavigatorSheet), findsOneWidget);
    expect(find.byKey(const Key('page-navigator-grid')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-3')), findsOneWidget);
  });

  testWidgets('点缩略图跳到对应页', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await tester.tap(find.byKey(const Key('reader-pages-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-thumb-3')));
    await tester.pumpAndSettle();

    expect(find.byType(PageNavigatorSheet), findsNothing);
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('关掉面板不改变页码', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await tester.tap(find.byKey(const Key('reader-pages-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-navigator-close')));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('缩略图加载失败只画占位，面板照常可用', (WidgetTester tester) async {
    final repository = FakeReaderRepository();
    await pumpReader(tester, repository: repository, book: demoReaderBook());
    // 打开面板之前让后续取图失败：缩略图应该退化成占位图标，而不是抛异常。
    repository.imageFailure = const NetworkFailure();

    await tester.tap(find.byKey(const Key('reader-pages-button')));
    await tester.pumpAndSettle();

    expect(find.byType(PageNavigatorSheet), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsWidgets);
  });
}
