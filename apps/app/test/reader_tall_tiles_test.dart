import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_tall_page_tile.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

void main() {
  testWidgets('纵向模式下超过 4096px 的超长条漫自动展开为分片纹理渲染', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(
        pageCount: 2,
        pageSizes: const <({int width, int height})>[
          (width: 800, height: 12000),
          (width: 800, height: 1200),
        ],
      ),
      book: demoReaderBook(),
      settle: false,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.vertical),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 真实异步分片解码需要 runAsync 等待帧解码完成。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderTallPageTile), findsWidgets);
    expect(find.byKey(const Key('reader-tall-tile-0-0')), findsOneWidget);
  });
}
