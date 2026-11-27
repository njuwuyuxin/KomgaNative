import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress_sink.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';

/// P1-4：通过注册表协议插件 + SourceBundle.progressSink + SourceCapabilities.syncsProgressRemotely
/// 零侵入接入 Kavita 与 OPDS 等第三种内容源。
void main() {
  test('StoredServer 序列化兼容旧版 JSON 并持久化非 Komga 的 kind（P1-4）', () {
    final legacy = StoredServer.fromJson(const <String, Object?>{
      'baseUrl': 'https://komga.legacy.test',
      'apiKey': 'k1',
      'accountEmail': 'a@b.c',
    });
    expect(legacy.kind, SourceKind.komga);

    final kavita = StoredServer(
      address: ServerAddress.parse('https://kavita.example.com'),
      apiKey: 'kv-token',
      accountEmail: 'reader@kavita.test',
      kind: SourceKind.kavita,
    );
    final roundTripped = StoredServer.fromJson(kavita.toJson());
    expect(roundTripped.kind, SourceKind.kavita);
    expect(roundTripped, kavita);

    final remote = remoteSourceOfServer(kavita);
    expect(remote.kind, SourceKind.kavita);
    expect(remote.capabilities.syncsProgressRemotely, isTrue);

    final opds = StoredServer(
      address: ServerAddress.parse('https://opds.example.com'),
      apiKey: 'opds-token',
      accountEmail: '',
      kind: SourceKind.opds,
    );
    final opdsSource = remoteSourceOfServer(opds);
    expect(opdsSource.kind, SourceKind.opds);
    expect(opdsSource.capabilities.syncsProgressRemotely, isFalse);
    expect(opdsSource.capabilities.supportsCollections, isFalse);
  });

  test('进度同步按 RemoteSourcePlugin.progressSink 与 syncsProgressRemotely 路由，无需 Komga 会话（P1-4）', () async {
    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final kavitaServer = StoredServer(
      address: ServerAddress.parse('https://kavita.p14.test'),
      apiKey: 'kv-key',
      accountEmail: 'u@kavita.test',
      kind: SourceKind.kavita,
    );
    final opdsServer = StoredServer(
      address: ServerAddress.parse('https://opds.p14.test'),
      apiKey: 'opds-key',
      accountEmail: '',
      kind: SourceKind.opds,
    );

    final kavitaUploaded = <ProgressTarget>[];
    final opdsUploaded = <ProgressTarget>[];

    final serverStore = InMemoryServerStore.withAll(<StoredServer>[
      kavitaServer,
      opdsServer,
    ]);

    final container = ProviderContainer(
      overrides: [
        progressDatabaseProvider.overrideWithValue(db),
        serverStoreProvider.overrideWithValue(serverStore),
        remoteSourcePluginsProvider.overrideWithValue(
          <SourceKind, RemoteSourcePlugin>{
            SourceKind.kavita: _FakeSourcePlugin(
              _RecordingProgressSink(kavitaUploaded),
            ),
            SourceKind.opds: _FakeSourcePlugin(
              _RecordingProgressSink(opdsUploaded),
            ),
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serverListProvider.future);
    final sync = container.read(progressSyncProvider);

    // 同时验证 SourceRegistry 能按 kind 懒构建出带 progressSink 的 SourceBundle。
    final registry = container.read(sourceRegistryProvider);
    expect(registry.bundleFor(kavitaServer.id).source.kind, SourceKind.kavita);
    expect(registry.bundleFor(opdsServer.id).source.kind, SourceKind.opds);

    // 1) Kavita 声明 syncsProgressRemotely == true：save + flush 经由 Kavita 的 ProgressSink 上传。
    await sync.save(
      'kv-book-1',
      page: 14,
      completed: false,
      scope: kavitaServer.id,
    );
    await sync.flush();

    expect(kavitaUploaded, hasLength(1));
    expect(kavitaUploaded.single.bookId, 'kv-book-1');
    expect(kavitaUploaded.single.page, 14);
    expect(await db.pending(scope: kavitaServer.id), isEmpty);

    // 2) OPDS 声明 syncsProgressRemotely == false：仅本地落盘，绝不入 outbox，也不调用 ProgressSink。
    await sync.save(
      'opds-book-1',
      page: 7,
      completed: false,
      scope: opdsServer.id,
    );
    await sync.flush();

    expect(opdsUploaded, isEmpty);
    expect(await db.pending(scope: opdsServer.id), isEmpty);
    final opdsRecord = await db.record('opds-book-1', scope: opdsServer.id);
    expect(opdsRecord, isNotNull);
    expect(opdsRecord!.page, 7);
    expect(opdsRecord.pendingSeq, isNull);
  });
}

final class _FakeSourcePlugin implements RemoteSourcePlugin {
  _FakeSourcePlugin(this._sink);

  final ProgressSink _sink;

  @override
  ProgressSink? buildProgressSink(Ref ref, StoredServer server) => _sink;

  @override
  SourceBundle? buildBundle(
    Ref ref,
    StoredServer server,
    ProgressSink progressSink,
  ) {
    final lib = FakeLibraryRepository();
    return SourceBundle(
      source: remoteSourceOfServer(server),
      library: lib,
      reader: FakeReaderRepository(),
      collections: lib,
      readStatus: lib,
      progressSink: progressSink,
    );
  }
}

final class _RecordingProgressSink implements ProgressSink {
  _RecordingProgressSink(this.uploaded);

  final List<ProgressTarget> uploaded;

  @override
  Future<void> uploadProgress(ProgressTarget target) async {
    uploaded.add(target);
  }
}
