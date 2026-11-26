import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu_reader/yomu_reader.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

void main() {
  test('ReaderConfig 颜色组重置与序列化正确处理 imageFilter', () {
    const cfg = ReaderConfig(imageFilter: ReaderImageFilter.einkCrisp);
    final decoded = ReaderConfig.fromJson(cfg.toJson());
    expect(decoded.imageFilter, ReaderImageFilter.einkCrisp);
    expect(cfg.isGroupDefault(ReaderSettingsGroup.color), isFalse);
    final reset = cfg.resetGroup(ReaderSettingsGroup.color);
    expect(reset.imageFilter, ReaderImageFilter.none);
    expect(reset.isGroupDefault(ReaderSettingsGroup.color), isTrue);
  });

  testWidgets('滤镜为 none 时不包裹额外 ColorFiltered 图层', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(imageFilter: ReaderImageFilter.none),
      ),
    );
    expect(find.byKey(const Key('reader-image-filter')), findsNothing);
  });

  testWidgets('开启墨水屏清晰增强后阅读区套用 ColorFiltered 矩阵', (WidgetTester tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      forceEink: true,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(imageFilter: ReaderImageFilter.einkCrisp),
      ),
    );
    expect(find.byKey(const Key('reader-image-filter')), findsOneWidget);
  });
}
