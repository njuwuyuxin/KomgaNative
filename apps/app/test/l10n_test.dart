import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/app.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/screens/settings_screen.dart';
import 'package:yomu/src/screens/splash_screen.dart';
import 'package:yomu/src/session/connection_service.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/fakes.dart';
import 'support/test_source_overrides.dart';

/// i18n：ARB 文案随 locale 切换、语言设置持久化、坏存档回 system。
void main() {
  /// 直接渲染设置页，用 MaterialApp 的 locale 指定语言。
  Future<void> pumpSettings(
    WidgetTester tester,
    Locale locale,
    HttpCacheDatabase db,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
          // 设置页会读缓存/下载占用：内存库不需要平台通道。
          httpCacheDatabaseProvider.overrideWithValue(db),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置页英文与中文的关键文案不同', (WidgetTester tester) async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await pumpSettings(tester, const Locale('en'), db);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    await pumpSettings(tester, const Locale('zh'), db);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('app 按语言设置切换 locale，并在切换后落盘', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = InMemorySettingsStore(const AppSettings(language: 'zh'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(
            InMemoryServerStore(storedServer()),
          ),
          connectionServiceProvider.overrideWithValue(FakeConnectionService()),
          progressStoreProvider.overrideWithValue(InMemoryProgressStore()),
          ...testSourceOverrides(
            library: FakeLibraryRepository(series: demoShelf()),
            reader: FakeReaderRepository(),
          ),
          settingsStoreProvider.overrideWithValue(store),
        ],
        child: const KomgaApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 存档是 zh：书架与底部导航都应该是中文。
    expect(find.text('书架'), findsWidgets);
    expect(find.text('Library'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);

    // 在界面上切到 English：文案立刻变，且写回存档。
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('设置'), findsNothing);
    expect(store.settings.language, 'en');
  });

  test('未知语言存档回 system（跟随系统）', () async {
    final store = InMemorySettingsStore(const AppSettings(language: 'klingon'));
    final container = ProviderContainer(
      overrides: <Override>[settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    // 读一次触发 build() 里的异步恢复；多等几个 microtask 穿透存储。
    expect(container.read(settingsProvider).language, AppLanguage.system);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(settingsProvider).language, AppLanguage.system);
  });

  test('appLanguageFromCode 对坏值一律回 system', () {
    for (final bad in <String?>[
      null,
      '',
      'klingon',
      'EN',
      'zh-Hans',
      '{"language":"zh"}',
    ]) {
      expect(appLanguageFromCode(bad), AppLanguage.system, reason: 'bad=$bad');
    }
    expect(appLanguageFromCode('en'), AppLanguage.en);
    expect(appLanguageFromCode('zh'), AppLanguage.zh);
  });

  testWidgets('客户端品牌名称统一显示为 Yomu（启动过渡页、开源许可页、API Key 标签）', (
    WidgetTester tester,
  ) async {
    expect(LiveConnectionService().deviceLabel, 'Yomu');

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const SplashScreen()),
    );
    expect(find.text('Yomu'), findsOneWidget);

    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpSettings(tester, const Locale('zh'), db);
    final licensesTile = find.byKey(const Key('settings-licenses'));
    await tester.scrollUntilVisible(
      licensesTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(licensesTile);
    await tester.pumpAndSettle();
    expect(find.text('Yomu'), findsWidgets);
  });
}
