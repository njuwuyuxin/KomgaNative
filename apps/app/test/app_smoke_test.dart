import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/app.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/session/connection_service.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';

import 'golden/golden_harness.dart';
import 'support/fake_library.dart';
import 'support/fakes.dart';

/// 端到端冒烟：真实路由 + 真实会话守卫 + 假网络/假钥匙串。
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpApp(
    WidgetTester tester, {
    required ServerStore store,
    ConnectionService? service,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(store),
          connectionServiceProvider.overrideWithValue(
            service ?? FakeConnectionService(),
          ),
          // 书架走假仓库：冒烟测试不该联网，也不能依赖真实服务器。
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository(series: demoShelf()),
          ),
        ],
        child: const KomgaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未登录 → 直接落在连接页（不闪现书架）', (WidgetTester tester) async {
    await pumpApp(tester, store: InMemoryServerStore());
    expect(find.text('Connect to your Komga server'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('已登录 → 冷启动直接进入书架，底部导航可见', (WidgetTester tester) async {
    await pumpApp(tester, store: InMemoryServerStore(storedServer()));
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('填写账号密码并连接 → 进入书架', (WidgetTester tester) async {
    final store = InMemoryServerStore();
    final service = FakeConnectionService();
    await pumpApp(tester, store: store, service: service);

    await tester.enterText(find.byType(TextField).at(0), 'komga.example.com');
    await tester.enterText(find.byType(TextField).at(1), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Frieren'), findsOneWidget);
    expect(service.passwordCalls, 1);
    expect((await store.load())!.accountEmail, 'me@example.com');
  });

  testWidgets('连接失败 → 停留在连接页并显示错误', (WidgetTester tester) async {
    await pumpApp(
      tester,
      store: InMemoryServerStore(),
      service: FakeConnectionService(
        onConnect: (ServerAddress address) async => throw authError(),
      ),
    );

    await tester.enterText(
      find.byType(TextField).at(0),
      'https://k.example.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'bad');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to your Komga server'), findsOneWidget);
    expect(find.textContaining('账号或密码不正确'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('切到 API Key 模式只需一个输入框', (WidgetTester tester) async {
    await pumpApp(tester, store: InMemoryServerStore());
    await tester.tap(find.text('API key'));
    await tester.pumpAndSettle();

    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('API key'), findsWidgets);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });
}
