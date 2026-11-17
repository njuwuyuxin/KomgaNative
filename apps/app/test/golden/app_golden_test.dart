import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';

import 'golden_harness.dart';

/// UI 基线矩阵。
///
/// 覆盖三件事：形态（手机/平板/墨水屏）、主题（light/dark/eink）、文本缩放。
/// 新增页面时必须同时新增基线，否则 CI 的黄金图任务没有意义。
void main() {
  setUpAll(loadAppFonts);

  testWidgets('library@phone_light', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const LibraryScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
    await expectGolden(tester, 'library@phone_light');
  });

  testWidgets('library@tablet_dark', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const LibraryScreen(),
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
    await expectGolden(tester, 'library@tablet_dark');
  });

  testWidgets('library@phone_light_text1.3', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const LibraryScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      textScale: 1.3,
    );
    await expectGolden(tester, 'library@phone_light_text1.3');
  });

  testWidgets('settings@eink', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SettingsScreen(),
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
    await expectGolden(tester, 'settings@eink');
  });

  testWidgets('reader@phone_dark', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ReaderScreen(bookId: 'b1'),
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
    );
    await expectGolden(tester, 'reader@phone_dark');
  });
}
