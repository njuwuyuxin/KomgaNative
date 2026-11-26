import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_preset_section.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P3-1：阅读预设的保存 / 应用 / 删除。
void main() {
  testWidgets('保存当前设置、改设置后一键应用回来', (WidgetTester tester) async {
    final store = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.single),
      ),
    );

    // 保存当前（single）为预设。
    await openSettings(tester);
    await tester.tap(find.byKey(const Key('reader-preset-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-preset-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPresetChip), findsOneWidget);
    expect(store.prefs?.presets, hasLength(1));
    await closeSheet(tester);

    // 改成 double，再从预设切回 single。
    await pickMode(tester, ReaderModeChoice.double);
    expect(store.prefs?.global.mode, ReaderModeChoice.double);

    await openSettings(tester);
    await tester.tap(find.byType(ReaderPresetChip));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    expect(store.prefs?.global.mode, ReaderModeChoice.single);
  });

  testWidgets('点 × 删除预设，不回答预设本身', (WidgetTester tester) async {
    final store = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.single),
      ),
    );

    await openSettings(tester);
    await tester.tap(find.byKey(const Key('reader-preset-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-preset-confirm')));
    await tester.pumpAndSettle();
    await closeSheet(tester);

    await openSettings(tester);
    final deleteIcon = find.descendant(
      of: find.byType(ReaderPresetChip),
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    expect(find.byType(ReaderPresetChip), findsNothing);
    expect(store.prefs?.presets, isEmpty);
  });
}
