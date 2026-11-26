import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/screens/settings_screen.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:drift/native.dart';

import 'support/fakes.dart';

/// 设置页：多服务器列表（切换/删除/新增）。
void main() {
  StoredServer otherServer() => StoredServer(
    address: ServerAddress.parse('https://other.example.com'),
    apiKey: 'other-key',
    accountEmail: 'other@example.com',
  );

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    required InMemoryServerStore store,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(store),
          // 设置页会读缓存/下载占用：内存库既不需要平台通道，也不会被本机缓存影响。
          httpCacheDatabaseProvider.overrideWithValue(
            HttpCacheDatabase(NativeDatabase.memory()),
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

  /// 滚到某个 key 可见。
  ///
  /// `SliverList` **不构建屏幕外的项**，所以 `ensureVisible` 会先失败——
  /// 得先 `scrollUntilVisible` 把它滚进来。
  /// 滚到某个 key 可见。
  ///
  /// SliverList **不构建屏幕外的项**，所以 ensureVisible 会先失败——
  /// 得先真的往下拖。这里直接对页面主滚动视图做 drag：scrollUntilVisible
  /// 在页面里还有横向分段控件时容易选错 scrollable。
  Future<void> revealKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    // 先往下找；找不到再往回（页面变短时目标可能跑到视口上方）。
    for (final step in <double>[-300, 300]) {
      for (var i = 0; i < 25 && finder.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          Offset(0, step),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      if (finder.evaluate().isNotEmpty) break;
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('列出已保存服务器，点另一台即切换', (WidgetTester tester) async {
    final first = storedServer();
    final second = otherServer();
    final container = await pumpSettings(
      tester,
      store: InMemoryServerStore.withAll(<StoredServer>[
        first,
        second,
      ], active: first),
    );

    await revealKey(tester, 'server-${first.id}');
    await revealKey(tester, 'server-${second.id}');

    await tester.tap(find.byKey(Key('server-${second.id}')));
    await tester.pumpAndSettle();

    final session = container.read(sessionProvider);
    expect(session, isA<SessionConnected>());
    expect((session as SessionConnected).server.id, second.id);
  });

  testWidgets('新增服务器 = 退出当前会话（列表保留）', (WidgetTester tester) async {
    final first = storedServer();
    final container = await pumpSettings(
      tester,
      store: InMemoryServerStore.withAll(<StoredServer>[first], active: first),
    );

    await revealKey(tester, 'server-add');
    await tester.tap(find.byKey(const Key('server-add')));
    await tester.pumpAndSettle();

    expect(container.read(sessionProvider), isA<SessionDisconnected>());
    await revealKey(tester, 'server-${first.id}');
    expect(find.byKey(Key('server-${first.id}')), findsOneWidget);
  });

  testWidgets('删除服务器：确认后从列表消失，当前服务器则一并退出', (WidgetTester tester) async {
    final first = storedServer();
    final second = otherServer();
    final container = await pumpSettings(
      tester,
      store: InMemoryServerStore.withAll(<StoredServer>[
        first,
        second,
      ], active: first),
    );

    await revealKey(tester, 'server-remove-${first.id}');
    await tester.tap(find.byKey(Key('server-remove-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Remove server?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('server-${first.id}')), findsNothing);
    await revealKey(tester, 'server-${second.id}');
    expect(find.byKey(Key('server-${second.id}')), findsOneWidget);
    expect(container.read(sessionProvider), isA<SessionDisconnected>());
  });
}
