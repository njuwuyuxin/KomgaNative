import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';
import 'support/test_source_overrides.dart';

/// UI-P3-2：按系列记住阅读设置。
void main() {
  testWidgets('开关打开后只写系列覆盖，不改全局；关闭后回到全局', (WidgetTester tester) async {
    final store = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.single),
      ),
    );
    final scopedS1 = ReaderPrefs.scopedKey(kTestKomgaSourceKey, 's1');

    await openSettings(tester);
    expect(find.byKey(const Key('reader-series-remember')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-series-remember')));
    await tester.pumpAndSettle();
    expect(store.prefs?.seriesOverrides, contains(scopedS1));

    // 开关已开：改模式只写 s1 的覆盖，全局仍是 single。
    await tester.tap(find.byKey(const Key('reader-mode-double')));
    await tester.pumpAndSettle();
    expect(
      store.prefs?.seriesOverrides[scopedS1]?.mode,
      ReaderModeChoice.double,
    );
    expect(store.prefs?.global.mode, ReaderModeChoice.single);
    await closeSheet(tester);

    // 再打开，关掉开关：覆盖被删掉。
    await openSettings(tester);
    await tester.tap(find.byKey(const Key('reader-series-remember')));
    await tester.pumpAndSettle();
    expect(store.prefs?.seriesOverrides, isEmpty);
    expect(store.prefs?.global.mode, ReaderModeChoice.single);
  });
}
