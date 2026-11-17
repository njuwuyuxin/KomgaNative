import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_reader.dart';
import 'fakes.dart';

/// 阅读器测试的公共装配：真路由之外的最小环境（假仓库 + 内存偏好 + 假常亮）。
///
/// 单独抽出来是因为阅读器的测试分成两片（基础模式 / 设置面板），
/// 两边必须用**同一套**装配，否则"到底谁在改偏好"会越测越糊涂。
Future<InMemoryReaderPrefsStore> pumpReader(
  WidgetTester tester, {
  FakeReaderRepository? repository,
  Book? book,
  ReadingDirection direction = ReadingDirection.leftToRight,
  bool forceEink = false,
  ReaderPrefs? initialPrefs,
  FakeWakeLock? wakeLock,
  ProgressStore? progressStore,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final prefsStore = InMemoryReaderPrefsStore(initialPrefs);
  final readerRepository = repository ?? FakeReaderRepository();
  // 进度同步用内存库 + 把上传直接交给假仓库：
  // 这样"翻页 → 落盘 → 提交"三段都能在测试里断言，又不会碰真 sqlite。
  final sync = ProgressSyncService(
    store: progressStore ?? InMemoryProgressStore(),
    upload: (ProgressTarget target) => readerRepository.uploadProgress(
      target.bookId,
      page: target.page,
      completed: target.completed,
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        readerRepositoryProvider.overrideWithValue(readerRepository),
        progressSyncProvider.overrideWithValue(sync),
        readerPrefsStoreProvider.overrideWithValue(prefsStore),
        wakeLockProvider.overrideWithValue(wakeLock ?? FakeWakeLock()),
        if (forceEink) settingsProvider.overrideWith(EinkSettings.new),
      ],
      child: MaterialApp(
        theme: forceEink ? AppTheme.eink() : AppTheme.dark(),
        home: ReaderScreen(bookId: 'b1', book: book, direction: direction),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefsStore;
}

/// 点屏幕右侧三分之一（LTR 的"下一页"）。
Future<void> tapRight(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
  await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
  await tester.pumpAndSettle();
}

Future<void> tapLeft(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
  await tester.tapAt(Offset(rect.left + rect.width * 0.05, rect.center.dy));
  await tester.pumpAndSettle();
}

/// 打开设置面板。
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-settings-button')));
  await tester.pumpAndSettle();
}

/// 点面板外的遮罩关掉面板。
Future<void> closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

/// 打开面板 → 选模式 → 关掉面板。
Future<void> pickMode(WidgetTester tester, ReaderModeChoice choice) async {
  await openSettings(tester);
  await tester.tap(find.byKey(Key('reader-mode-${choice.name}')));
  await tester.pumpAndSettle();
  await closeSheet(tester);
}
