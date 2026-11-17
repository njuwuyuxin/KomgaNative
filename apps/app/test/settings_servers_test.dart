import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
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

    expect(find.byKey(Key('server-${first.id}')), findsOneWidget);
    expect(find.byKey(Key('server-${second.id}')), findsOneWidget);

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

    await tester.tap(find.byKey(const Key('server-add')));
    await tester.pumpAndSettle();

    expect(container.read(sessionProvider), isA<SessionDisconnected>());
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

    await tester.tap(find.byKey(Key('server-remove-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Remove server?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('server-${first.id}')), findsNothing);
    expect(find.byKey(Key('server-${second.id}')), findsOneWidget);
    expect(container.read(sessionProvider), isA<SessionDisconnected>());
  });
}
