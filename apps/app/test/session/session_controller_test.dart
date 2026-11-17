import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/session/connection_service.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';

import '../support/fakes.dart';

void main() {
  ProviderContainer containerWith({
    ServerStore? store,
    ConnectionService? service,
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        serverStoreProvider.overrideWithValue(store ?? InMemoryServerStore()),
        connectionServiceProvider.overrideWithValue(
          service ?? FakeConnectionService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    // 预热：Notifier 懒构建，不读一次就不会触发 build() 里的恢复流程。
    container.read(sessionProvider);
    return container;
  }

  /// 让 build() 里 unawaited 的恢复流程跑完（多次 microtask 才能穿透 async 存储）。
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('没有已保存会话 → 未连接', () async {
    final container = containerWith();
    expect(container.read(sessionProvider), isA<SessionLoading>());
    await settle();
    expect(container.read(sessionProvider), isA<SessionDisconnected>());
  });

  test('有已保存会话 → 直接进入已连接（冷启动免登录）', () async {
    final container = containerWith(store: InMemoryServerStore(storedServer()));
    await settle();
    final state = container.read(sessionProvider);
    expect(state, isA<SessionConnected>());
    expect((state as SessionConnected).server.accountEmail, 'me@example.com');
  });

  test('密码连接成功 → 保存 Key 并进入已连接', () async {
    final store = InMemoryServerStore();
    final service = FakeConnectionService();
    final container = containerWith(store: store, service: service);
    await settle();

    await container
        .read(sessionProvider.notifier)
        .connectWithPassword(
          rawUrl: 'komga.example.com',
          username: 'me@example.com',
          password: 'secret',
        );

    expect(container.read(sessionProvider), isA<SessionConnected>());
    expect(service.passwordCalls, 1);
    expect(service.lastAddress!.baseUrl, 'https://komga.example.com');
    expect((await store.load())!.apiKey, 'KEY-1');
  });

  test('API Key 连接成功 → 不调用密码接口', () async {
    final service = FakeConnectionService();
    final container = containerWith(service: service);
    await settle();

    await container
        .read(sessionProvider.notifier)
        .connectWithApiKey(
          rawUrl: 'https://k.example.com',
          apiKey: '  PASTED-KEY  ',
        );

    expect(container.read(sessionProvider), isA<SessionConnected>());
    expect(service.passwordCalls, 0);
    expect(service.apiKeyCalls, 1);
    expect(service.lastApiKey, 'PASTED-KEY', reason: '首尾空格应被裁掉');
  });

  test('401 → 提示账号密码错误，且不保存任何东西', () async {
    final store = InMemoryServerStore();
    final container = containerWith(
      store: store,
      service: FakeConnectionService(
        onConnect: (ServerAddress address) async => throw authError(),
      ),
    );
    await settle();

    await container
        .read(sessionProvider.notifier)
        .connectWithPassword(
          rawUrl: 'https://k.example.com',
          username: 'me@example.com',
          password: 'bad',
        );

    final state = container.read(sessionProvider) as SessionDisconnected;
    expect(state.error, '账号或密码不正确');
    expect(state.submitting, isFalse);
    expect(await store.load(), isNull);
  });

  test('网络错误 → 报错里带上主机名，方便用户判断是不是地址错了', () async {
    final container = containerWith(
      service: FakeConnectionService(
        onConnect: (ServerAddress address) async => throw networkError(),
      ),
    );
    await settle();

    await container
        .read(sessionProvider.notifier)
        .connectWithPassword(
          rawUrl: 'http://192.168.1.10:25600',
          username: 'u',
          password: 'p',
        );

    final state = container.read(sessionProvider) as SessionDisconnected;
    expect(state.error, contains('192.168.1.10'));
    expect(state.hint, isNotNull);
  });

  test('地址非法 → 本地拦截，不发请求', () async {
    final service = FakeConnectionService();
    final container = containerWith(service: service);
    await settle();

    await container
        .read(sessionProvider.notifier)
        .connectWithPassword(rawUrl: 'not a url', username: 'u', password: 'p');

    final state = container.read(sessionProvider) as SessionDisconnected;
    expect(state.error, isNotNull);
    expect(state.hint, contains('https://'));
    expect(service.passwordCalls, 0);
  });

  test('退出登录 → 清空存储并回到未连接', () async {
    final store = InMemoryServerStore(storedServer());
    final container = containerWith(store: store);
    await settle();
    expect(container.read(sessionProvider), isA<SessionConnected>());

    await container.read(sessionProvider.notifier).signOut();

    expect(container.read(sessionProvider), isA<SessionDisconnected>());
    expect(await store.load(), isNull);
  });
}
