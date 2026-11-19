import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/app_info_provider.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

/// FIX-09：版本号必须来自构建产物，不再是硬编码的 `0.1.0 (v1)`。
void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required AppInfo info,
  }) async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
          httpCacheDatabaseProvider.overrideWithValue(db),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          appInfoProvider.overrideWith((Ref ref) async => info),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('版本行显示构建版本与构建号', (WidgetTester tester) async {
    await pumpSettings(
      tester,
      info: const AppInfo(version: '2.3.4', buildNumber: '42'),
    );

    // "关于"分组在页面底部：先滚过去。
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-version')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('2.3.4 (42)'), findsOneWidget);
    expect(find.text('0.1.0 (v1)'), findsNothing);
  });

  testWidgets('没有构建号时只显示版本，不显示空括号', (WidgetTester tester) async {
    await pumpSettings(
      tester,
      info: const AppInfo(version: '2.3.4', buildNumber: ''),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-version')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('2.3.4'), findsOneWidget);
  });
}
