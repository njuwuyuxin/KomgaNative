import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P3-4：锁定缩放。
void main() {
  testWidgets('锁定缩放：放大后翻页，比例保持', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(lockZoom: true),
    );
    final base = tester.getRect(find.byKey(const Key('reader-image-0')));

    await doubleTapMiddle(tester);
    final zoomed = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(zoomed.width, closeTo(base.width * 2.5, 4));

    await tapRight(tester);
    expect(find.text('2 / 3'), findsOneWidget);

    final next = tester.getRect(find.byKey(const Key('reader-image-1')));
    expect(next.width, closeTo(base.width * 2.5, 8), reason: '翻页后比例不缩回');
  });

  testWidgets('未锁定缩放：放大状态下点翻页区不翻页', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    await doubleTapMiddle(tester);

    await tapRight(tester);
    expect(find.text('1 / 3'), findsOneWidget);
  });
}
