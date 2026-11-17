import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/screens/connection_screen.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/screens/splash_screen.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';

import '../support/fakes.dart';
import 'golden_harness.dart';

/// UI 基线矩阵。
///
/// 覆盖三件事：形态（手机/平板/墨水屏）、主题（light/dark/eink）、文本缩放。
/// 新增页面时必须同时新增基线，否则这条流水线没有意义。
void main() {
  setUpAll(loadAppFonts);

  /// 依赖会话的页面统一注入内存实现，避免钥匙串通道缺失把错误渲染进基线。
  List<Override> memorySession({bool connected = false}) => <Override>[
    serverStoreProvider.overrideWithValue(
      InMemoryServerStore(connected ? storedServer() : null),
    ),
  ];

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
      overrides: memorySession(connected: true),
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

  testWidgets('connection@phone_light', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ConnectionScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      overrides: memorySession(),
    );
    await expectGolden(tester, 'connection@phone_light');
  });

  testWidgets('connection@eink', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ConnectionScreen(),
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      overrides: memorySession(),
    );
    await expectGolden(tester, 'connection@eink');
  });

  testWidgets('splash@phone_light', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SplashScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      settle: false,
    );
    await expectGolden(tester, 'splash@phone_light');
  });
}
