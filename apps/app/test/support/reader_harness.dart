import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/drift_http_cache.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu_sync/yomu_sync.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_reader.dart';
import 'fakes.dart';
import 'test_source_overrides.dart';

/// 阅读器测试的公共装配：真路由之外的最小环境（假仓库 + 内存偏好 + 假常亮）。
///
/// 单独抽出来是因为阅读器的测试分成两片（基础模式 / 设置面板），
/// 两边必须用**同一套**装配，否则"到底谁在改偏好"会越测越糊涂。
Future<InMemoryReaderPrefsStore> pumpReader(
  WidgetTester tester, {
  FakeReaderRepository? repository,
  LibraryRepository? library,
  Book? book,
  String bookId = 'b1',
  ReadingDirection direction = ReadingDirection.leftToRight,
  bool forceEink = false,
  ReaderPrefs? initialPrefs,
  FakeWakeLock? wakeLock,
  FakeHardwareKeys? hardwareKeys,
  FakeImageSaver? imageSaver,
  ProgressStore? progressStore,
  bool offline = false,
  String? heroTag,
  bool settle = true,
  Size? viewSize,
  void Function(Book next)? onOpenNext,
  Future<void> Function(int page)? onSharePage,
  List<Override> extraOverrides = const <Override>[],
}) async {
  tester.view.physicalSize = viewSize ?? const Size(390 * 3, 844 * 3);
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

  /// 离线提示由缓存实例广播；先经两次核心失败确认离线，再建树，顶栏图标才会在首帧出现。
  final cache = DriftHttpCache(
    HttpCacheDatabase(NativeDatabase.memory()),
    now: () => DateTime.utc(2026, 11, 25, 12),
  );
  addTearDown(cache.dispose);
  if (offline) {
    cache
      ..reportOffline('https://komga.example.com')
      ..reportOffline('https://komga.example.com');
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...testSourceOverrides(library: library, reader: readerRepository),
        progressSyncProvider.overrideWithValue(sync),
        readerPrefsStoreProvider.overrideWithValue(prefsStore),
        wakeLockProvider.overrideWithValue(wakeLock ?? FakeWakeLock()),
        imageSaverProvider.overrideWithValue(imageSaver ?? FakeImageSaver()),
        hardwareKeysProvider.overrideWithValue(
          hardwareKeys ?? FakeHardwareKeys(),
        ),
        httpCacheProvider.overrideWithValue(cache),
        if (forceEink) settingsProvider.overrideWith(EinkSettings.new),
        ...extraOverrides,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: forceEink ? AppTheme.eink() : AppTheme.dark(),
        home: ReaderScreen(
          bookId: bookId,
          book: book,
          direction: direction,
          heroTag: heroTag,
          onOpenNext: onOpenNext,
          onSharePage: onSharePage,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
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

/// 点一下只推进**一帧**：看得见"翻页后的第一帧"到底是什么。
///
/// `pumpAndSettle` 会把中间的 loading 帧全部吞掉，正好掩盖"闪一下"这类问题。
Future<void> tapRightOneFrame(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
  await tester.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
  await tester.pump();
}

Future<void> tapLeftOneFrame(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
  await tester.tapAt(Offset(rect.left + rect.width * 0.05, rect.center.dy));
  await tester.pump();
}

/// 点一下屏幕中间：切换 chrome。
///
/// 中间区域要等双击判定窗口（[kDoubleTapTimeout]）过去，单击才生效——
/// 不然双击缩放的第一下就把 chrome 切掉了。所以这里必须推进一段假时间，
/// 光 `pumpAndSettle` 不够（没有待处理的帧，定时器不会被推进）。
Future<void> tapMiddle(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
  await tester.tapAt(rect.center);
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

/// 双击屏幕中间：放大到 2.5 倍（已放大时还原）。
Future<void> doubleTapMiddle(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
  await tester.tapAt(rect.center);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(rect.center);
  await tester.pumpAndSettle();
}

/// 打开顶栏"更多"菜单（RDR-03：目录/隐身/缩略图/设置/分享都收在这里）。
Future<void> openReaderMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-more-button')));
  await tester.pumpAndSettle();
}

/// 从"更多"菜单里点一项（`reader-settings-button` 等 key 仍挂在菜单项上）。
Future<void> tapReaderMenu(WidgetTester tester, String key) async {
  await openReaderMenu(tester);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 打开完整设置面板。
Future<void> openSettings(WidgetTester tester) async {
  await tapReaderMenu(tester, 'reader-settings-button');
}

/// 打开 AA 快捷设置（RDR-03）。
Future<void> openQuickSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-quick-settings-button')));
  await tester.pumpAndSettle();
}

/// 打开缩略图/跳页面板。
Future<void> openPages(WidgetTester tester) async {
  await tapReaderMenu(tester, 'reader-pages-button');
}

/// 把面板里的控件滚到可见。
///
/// 面板比屏幕高（模式 / 适配 / 方向 / 背景 / 亮度 / 常亮 / 跳页），
/// 直接点下面的控件会落到屏幕外，`tap` 只会打印一条 warning 然后什么也不做。
Future<void> revealInSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// 点面板外的遮罩关掉面板。
Future<void> closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

/// 打开面板 → 选某一项（`reader-fit-cover` 之类）→ 关掉面板。
Future<void> pickOption(WidgetTester tester, String key) async {
  await openSettings(tester);
  final finder = find.byKey(Key(key));
  await revealInSheet(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await closeSheet(tester);
}

/// 打开面板 → 选模式 → 关掉面板。
Future<void> pickMode(WidgetTester tester, ReaderModeChoice choice) async {
  await pickOption(tester, 'reader-mode-${choice.name}');
}
