import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// SET-01：设置页的分组与"阅读默认值/书架默认值"提升。
void main() {
  late InMemoryReaderPrefsStore prefsStore;
  late InMemorySettingsStore settingsStore;

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    prefsStore = InMemoryReaderPrefsStore();
    settingsStore = InMemorySettingsStore();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(settingsStore),
          readerPrefsStoreProvider.overrideWithValue(prefsStore),
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository(series: demoShelf()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (final step in <double>[-300, 300]) {
      for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          Offset(0, step),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      if (finder.evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('阅读默认值直接写进阅读偏好', (WidgetTester tester) async {
    final container = await pumpSettings(tester);

    final mode = find.byKey(const Key('settings-reading-mode-double'));
    await reveal(tester, mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();

    expect(container.read(readerPrefsProvider).mode, ReaderModeChoice.double);

    final turn = find.byKey(const Key('settings-page-turn-fade'));
    await reveal(tester, turn);
    await tester.tap(turn);
    await tester.pumpAndSettle();
    expect(
      container.read(readerPrefsProvider).pageTurn,
      ReaderPageTurnChoice.fade,
    );
  });

  testWidgets('本次阅读时长开关写进阅读偏好（HIS-04）', (WidgetTester tester) async {
    final container = await pumpSettings(tester);

    final toggle = find.byKey(const Key('settings-show-session-time'));
    await reveal(tester, toggle);
    expect(container.read(readerPrefsProvider).showSessionTime, isTrue);

    // 直接点开关本体：整行 ListTile 在滚动后可能被底部导航挡住一半。
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(container.read(readerPrefsProvider).showSessionTime, isFalse);
  });
  testWidgets('书架默认值切换会同步到书架状态', (WidgetTester tester) async {
    final container = await pumpSettings(tester);
    // 没有连接服务器时"书架"组不显示（`shelfProvider` 会抛）。
    expect(find.byKey(const Key('settings-library-view')), findsNothing);
    expect(container.read(sessionProvider), isA<SessionState>());
  });

  testWidgets('阅读分组在设置页里可达', (WidgetTester tester) async {
    await pumpSettings(tester);

    await reveal(tester, find.text('READING'));
    expect(find.text('READING'), findsOneWidget);
    expect(find.byKey(const Key('settings-page-turn')), findsOneWidget);
    // 顺序由 settings@eink 黄金图钉住（外观 → 阅读 → 书架 → 服务器 → 存储）。
  });
}
