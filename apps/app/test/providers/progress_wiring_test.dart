import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:yomu_sync/yomu_sync.dart';

/// 回归：进度上传不能经由仓库，否则 `仓库 → 同步服务 → 仓库` 形成循环依赖。
///
/// 真机上表现为"翻页了、界面也动了，但服务端永远收不到"，日志里是
/// CircularDependencyError（2026-11-17 实测踩到）。这里把整张 provider 图建起来
/// 并真的跑一次 flush：有环就会抛，没环就只是普通的网络失败。
void main() {
  test('建图 + flush 不会形成循环依赖', () async {
    const baseUrl = 'http://127.0.0.1:1';
    final store = InMemoryProgressStore();
    await store.enqueue(
      const ProgressTarget(bookId: 'b1', page: 3, completed: false),
      scope: baseUrl,
    );

    final container = ProviderContainer(
      overrides: <Override>[
        // 指向一个必然连不上的地址：要的是"图能建起来"，不是真发请求。
        serverStoreProvider.overrideWithValue(
          InMemoryServerStore(
            StoredServer(
              address: ServerAddress.parse(baseUrl),
              apiKey: 'KEY',
              accountEmail: 'me@example.com',
            ),
          ),
        ),
        progressStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    // 建立会话（build() 里的恢复是异步的）。
    container.read(sessionProvider);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(sessionProvider), isA<SessionConnected>());

    // 同一会话内：书架、收藏集、已读状态、阅读器与进度补交全部共享唯一 KomgaSession 实例（ARC-09）。
    final shared = container.read(komgaSessionProvider);
    expect(shared, isNotNull);
    final libRepo =
        container.read(libraryRepositoryProvider) as KomgaLibraryRepository;
    final colRepo = container.read(
      collectionsRepositoryProvider,
    ) as KomgaCollectionsRepository;
    final statusRepo = container.read(
      readStatusRepositoryProvider,
    ) as KomgaReadStatusRepository;
    final rdrRepo =
        container.read(readerRepositoryProvider) as KomgaReaderRepository;
    expect(identical(libRepo.debugSession, shared), isTrue);
    expect(identical(colRepo.debugSession, shared), isTrue);
    expect(identical(statusRepo.debugSession, shared), isTrue);
    expect(identical(rdrRepo.debugSession, shared), isTrue);
    await container.read(progressSyncProvider).flush();

    // 连不上 → 进度必须留在队列里，而不是被当成已提交丢掉。
    expect(await store.pending(scope: baseUrl), hasLength(1));
  });

  for (final badStatus in <int>[404, 400]) {
    test('队首书籍返回 $badStatus 时直接出队，不阻塞第 2 本书（204）正常上传', () async {
      final receivedPaths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((HttpRequest req) async {
        await req.drain<void>();
        receivedPaths.add(req.uri.path);
        if (req.uri.path.endsWith('/b-dead/read-progress')) {
          req.response.statusCode = badStatus;
        } else {
          req.response.statusCode = 204;
        }
        await req.response.close();
      });

      final baseUrl = 'http://127.0.0.1:${server.port}';
      final store = InMemoryProgressStore();
      await store.enqueue(
        const ProgressTarget(bookId: 'b-dead', page: 99, completed: false),
        scope: baseUrl,
      );
      await store.enqueue(
        const ProgressTarget(bookId: 'b-good', page: 5, completed: false),
        scope: baseUrl,
      );

      final container = ProviderContainer(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(
            InMemoryServerStore(
              StoredServer(
                address: ServerAddress.parse(baseUrl),
                apiKey: 'KEY',
                accountEmail: 'me@example.com',
              ),
            ),
          ),
          progressStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionProvider);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      await container.read(progressSyncProvider).flush();

      expect(receivedPaths, <String>[
        '/api/v1/books/b-dead/read-progress',
        '/api/v1/books/b-good/read-progress',
      ]);
      expect(
        await store.pending(scope: baseUrl),
        isEmpty,
        reason: '坏死项与成功项都已出队，不死循环',
      );
    });
  }

  test('N2: 冷启动服务器列表未就绪时保存云端书进度，必须先入队并在列表就绪后补传', () async {
    final receivedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((HttpRequest req) async {
      await req.drain<void>();
      receivedPaths.add(req.uri.path);
      req.response.statusCode = 204;
      await req.response.close();
    });

    final baseUrl = 'http://127.0.0.1:${server.port}';
    final stored = StoredServer(
      address: ServerAddress.parse(baseUrl),
      apiKey: 'KEY',
      accountEmail: 'me@example.com',
    );
    final listCompleter = Completer<List<StoredServer>>();
    final store = InMemoryProgressStore();

    final container = ProviderContainer(
      overrides: <Override>[
        serverStoreProvider.overrideWithValue(InMemoryServerStore()),
        serverListProvider.overrideWith((Ref ref) => listCompleter.future),
        progressStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    // 保持 progressSyncProvider 活跃（等同真实应用挂载）。
    final sub = container.listen(progressSyncProvider, (_, _) {});
    addTearDown(sub.close);

    // 冷启动期间 serverListProvider 尚未完成，此时翻页保存云端书进度。
    await container
        .read(progressSyncProvider)
        .save('b-cold', page: 7, completed: false, scope: baseUrl);

    // 必须保留在上传队列里，绝不能被误判为"本地/不支持同步"直接丢弃。
    final queued = await store.pending(scope: baseUrl);
    expect(queued, hasLength(1));
    expect(queued.single.target.page, 7);

    // 服务器列表加载完毕后自动冲洗并上传到真实服务器。
    listCompleter.complete(<StoredServer>[stored]);
    await container.read(serverListProvider.future);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (receivedPaths.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(receivedPaths, <String>['/api/v1/books/b-cold/read-progress']);
    expect(await store.pending(scope: baseUrl), isEmpty);
  });
}
