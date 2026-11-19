import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/app.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/session/connection_service.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/floating_nav_bar.dart';

import 'golden/golden_harness.dart';
import 'support/fake_library.dart';
import 'support/fake_reader.dart';
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
          // 进度同步走内存库：冒烟测试不该打开 sqlite，也不该碰 path_provider 通道。
          progressStoreProvider.overrideWithValue(InMemoryProgressStore()),
          // 书架与阅读器都走假仓库：冒烟测试不该联网，也不能依赖真实服务器。
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository(series: demoShelf()),
          ),
          readerRepositoryProvider.overrideWithValue(
            FakeReaderRepository(pageCount: 19),
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
    // 手机形态是自定义的悬浮玻璃导航（不再是 Material 的 NavigationBar）。
    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
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
        onConnect: (ServerAddress address, _) async => throw authError(),
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

  testWidgets('从书架点进系列详情，再点进阅读器', (WidgetTester tester) async {
    await pumpApp(tester, store: InMemoryServerStore(storedServer()));

    await tester.tap(find.text('Frieren'));
    await tester.pumpAndSettle();
    expect(find.text('5 of 12 read'), findsOneWidget);
    expect(find.textContaining('Vol. 1'), findsOneWidget);

    await tester.tap(find.textContaining('Vol. 1'));
    await tester.pumpAndSettle();
    // 这本书服务端进度在第 5 页，阅读器应从上次位置继续，而不是从头开始。
    expect(find.text('5 / 19'), findsOneWidget);
  });

  /// 复现真实 NAS 的两种失败：地址写成 http（反代 400）+ 证书过期。
  testWidgets('http 端口 → 自动换 https，证书过期则先问用户', (WidgetTester tester) async {
    final store = InMemoryServerStore();
    final service = FakeConnectionService(
      onConnect: (ServerAddress address, TlsTrust trust) async {
        // 明文打到 HTTPS 端口：反代直接 400（实测 openresty 行为）。
        if (!address.isHttps) throw httpsRequiredError();
        // 证书过期：系统不认，必须用户确认后才放行（只放行这一张）。
        if (trust.isStrict) throw tlsError();
        return connectedOutcome(address);
      },
    );
    await pumpApp(tester, store: store, service: service);

    await tester.enterText(
      find.byType(TextField).at(0),
      'http://manga.example.com:4433',
    );
    await tester.enterText(find.byType(TextField).at(1), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    // 停在连接页，把证书细节摊开，而不是丢一个 "400" 或"网络错误"。
    expect(find.byKey(const Key('certificate-panel')), findsOneWidget);
    expect(find.textContaining('*.yasai.site'), findsOneWidget);
    expect(find.textContaining('74:F8:1F:E1:67:D9:9B:4C'), findsOneWidget);
    expect(find.textContaining('expired on 2026-07-19'), findsOneWidget);
    expect(await store.load(), isNull, reason: '确认之前不落盘');

    await tester.tap(find.text('Connect anyway'));
    await tester.pumpAndSettle();

    // 确认后进书架，并只固定这一张证书。
    expect(find.text('Frieren'), findsWidgets);
    final saved = (await store.load())!;
    expect(saved.address.isHttps, isTrue, reason: '自动升级后的 https 地址才是能用的');
    expect(saved.certificateFingerprint, expiredCertificate().derSha256);
  });

  testWidgets('证书面板点 Cancel → 留在连接页，不保存', (WidgetTester tester) async {
    final store = InMemoryServerStore();
    await pumpApp(
      tester,
      store: store,
      service: FakeConnectionService(
        onConnect: (ServerAddress address, _) async => throw tlsError(),
      ),
    );

    await tester.tap(find.text('API key'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://manga.example.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'KEY');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('certificate-panel')), findsNothing);
    expect(find.text('Connect to your Komga server'), findsOneWidget);
    expect(await store.load(), isNull);
  });
}
