import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_page.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

void main() {
  test('ReaderConfig 序列化与重置正确处理 splitWidePages', () {
    const cfg = ReaderConfig(splitWidePages: WidePageSplitMode.autoPortrait);
    final decoded = ReaderConfig.fromJson(cfg.toJson());
    expect(decoded.splitWidePages, WidePageSplitMode.autoPortrait);
    expect(cfg.isGroupDefault(ReaderSettingsGroup.layout), isFalse);
    final reset = cfg.resetGroup(ReaderSettingsGroup.layout);
    expect(reset.splitWidePages, WidePageSplitMode.off);
    expect(reset.isGroupDefault(ReaderSettingsGroup.layout), isTrue);
  });

  testWidgets('竖屏 RTL 宽页自动切分为先右后左，并支持临时合页查看与翻离自动恢复', (
    WidgetTester tester,
  ) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(
        pageCount: 3,
        pageSizes: const <({int width, int height})>[
          (width: 800, height: 1200),
          (width: 1800, height: 1200),
          (width: 800, height: 1200),
        ],
      ),
      book: demoReaderBook(),
      direction: ReadingDirection.rightToLeft,
      viewSize: const Size(390 * 3, 844 * 3),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(
          mode: ReaderModeChoice.single,
          splitWidePages: WidePageSplitMode.autoPortrait,
          pageTurn: ReaderPageTurnChoice.none,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第 1 页是普通竖页：不切分、不显示临时合页胶囊。
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(find.byKey(const Key('reader-temp-merge-pill')), findsNothing);

    // RTL 点左侧翻下一页 → 进入第 2 页宽图，RTL 先看右半页。
    await tapLeft(tester);
    expect(find.byKey(const Key('reader-image-1-right')), findsOneWidget);
    expect(find.byKey(const Key('reader-temp-merge-pill')), findsOneWidget);
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage).first).half,
      PageHalf.right,
    );

    // 点「合页查看」→ 临时合并显示整张宽图。
    await tester.tap(find.byKey(const Key('reader-temp-merge-pill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-image-1')), findsOneWidget);
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage).first).half,
      PageHalf.full,
    );

    // 再点「恢复切分」→ 回到半幅切分。
    await tester.tap(find.byKey(const Key('reader-temp-merge-pill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-image-1-right')), findsOneWidget);

    // 再翻下一页 → 仍在物理第 2 页，但切到左半页。
    await tapLeft(tester);
    expect(find.byKey(const Key('reader-image-1-left')), findsOneWidget);
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage).first).half,
      PageHalf.left,
    );

    // 再翻下一页 → 进入第 3 页普通竖页，合页胶囊消失。
    await tapLeft(tester);
    expect(find.byKey(const Key('reader-image-2')), findsOneWidget);
    expect(find.byKey(const Key('reader-temp-merge-pill')), findsNothing);
  });
}
