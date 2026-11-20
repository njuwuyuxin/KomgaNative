import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/widgets/reader_page.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P3-10：开启去白边后，页图走裁剪绘制层而不是原图直出。
void main() {
  testWidgets('白边页图开启 trimBorders 后使用裁剪绘制', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(
        pageNames: const <String>['trim_border'],
      ),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(global: ReaderConfig(trimBorders: true)),
    );

    // 边框检测是真实异步解码，假时钟推不动。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage).first),
    );
    expect(container.read(readerPrefsProvider).global.trimBorders, isTrue);

    expect(
      tester.widget<ReaderPagedView>(find.byType(ReaderPagedView)).trimBorders,
      isTrue,
    );
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage).first).trimBorders,
      isTrue,
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('reader-image-0')),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    expect(find.byType(ReaderPage), findsWidgets);
  });
}
