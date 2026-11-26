import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/local/local_collections_repository.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_library_repository.dart';
import 'package:yomu/src/data/local/local_read_status_repository.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/archive_password_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 单一内容源完整装配单元（四大领域仓库 + 源能力描述符）。
///
/// 后续扩展 Kavita / OPDS 时只需实现对应的 `SourceBundle` 挂入 [SourceRegistry]，
/// 上层 UI 与状态机零改动。
final class SourceBundle {
  const SourceBundle({
    required this.source,
    required this.library,
    required this.reader,
    required this.collections,
    required this.readStatus,
  });

  final ContentSource source;
  final LibraryRepository library;
  final ReaderRepository reader;
  final CollectionsRepository collections;
  final ReadStatusRepository readStatus;
}

/// 多源插件注册表：按 `sourceKey` 寻址对应的 [SourceBundle]。
final class SourceRegistry {
  SourceRegistry({
    required this.localBundle,
    required Map<String, SourceBundle> remoteBundles,
  }) : _remoteBundles = Map<String, SourceBundle>.unmodifiable(remoteBundles);

  final SourceBundle localBundle;
  final Map<String, SourceBundle> _remoteBundles;

  List<ContentSource> get sources => <ContentSource>[
    localBundle.source,
    for (final bundle in _remoteBundles.values) bundle.source,
  ];

  bool get hasRemoteSources => _remoteBundles.isNotEmpty;

  SourceBundle bundleFor(String? sourceKey) {
    if (sourceKey == null || isLocalSourceKey(sourceKey)) {
      return localBundle;
    }
    return _remoteBundles[sourceKey] ?? localBundle;
  }

  SourceBundle? remoteBundleOrNull(String sourceKey) =>
      _remoteBundles[sourceKey];
}

/// 本地受管沙盒存储目录（单测可 override 为临时目录）。
final Provider<LocalComicsStorage> localComicsStorageProvider =
    Provider<LocalComicsStorage>((Ref ref) => LocalComicsStorage());

/// 本机内置源仓库实例（独立暴露以便在测试中检查或清除封面缓存）。
final Provider<LocalLibraryRepository> localLibraryRepositoryProvider =
    Provider<LocalLibraryRepository>((Ref ref) {
      return LocalLibraryRepository(
        ref.watch(progressDatabaseProvider),
        ref.watch(localComicsStorageProvider),
      );
    });

final Provider<LocalReaderRepository> localReaderRepositoryProvider =
    Provider<LocalReaderRepository>((Ref ref) {
      final repo = LocalReaderRepository(
        ref.watch(progressDatabaseProvider),
        ref.watch(localComicsStorageProvider),
        passwordStore: ref.watch(archivePasswordStoreProvider),
      );
      ref.onDispose(repo.dispose);
      return repo;
    });

final Provider<SourceBundle> localSourceBundleProvider = Provider<SourceBundle>(
  (Ref ref) {
    final db = ref.watch(progressDatabaseProvider);
    final sync = ref.watch(progressSyncProvider);
    return SourceBundle(
      source: const LocalContentSource(),
      library: ref.watch(localLibraryRepositoryProvider),
      reader: ref.watch(localReaderRepositoryProvider),
      collections: LocalCollectionsRepository(db),
      readStatus: LocalReadStatusRepository(db, sync),
    );
  },
);

RemoteContentSource remoteSourceOfServer(StoredServer server) =>
    RemoteContentSource(
      sourceKey: server.id,
      displayName: server.label,
      subtitle: server.address.baseUrl,
    );

/// 全局多源注册表：自动汇聚常驻本机源 + 已保存/已连接的所有 Komga 服务器源。
final Provider<SourceRegistry> sourceRegistryProvider =
    Provider<SourceRegistry>((Ref ref) {
      final local = ref.watch(localSourceBundleProvider);
      final sessionState = ref.watch(sessionProvider);
      final activeKomga = ref.watch(komgaSessionProvider);
      final savedServers =
          ref.watch(serverListProvider).value ?? const <StoredServer>[];
      final cache = ref.watch(httpCacheProvider);
      final sync = ref.watch(progressSyncProvider);

      final serversById = <String, StoredServer>{
        for (final s in savedServers) s.id: s,
        if (sessionState is SessionConnected)
          sessionState.server.id: sessionState.server,
      };

      final extraSessions = <KomgaSession>[];
      final remotes = <String, SourceBundle>{};

      for (final server in serversById.values) {
        final KomgaSession session;
        if (activeKomga != null &&
            activeKomga.address.baseUrl == server.address.baseUrl) {
          session = activeKomga;
        } else {
          session = KomgaSession.withApiKey(
            address: server.address,
            apiKey: server.apiKey,
            trust: server.tls,
            cache: cache,
          );
          extraSessions.add(session);
        }
        remotes[server.id] = SourceBundle(
          source: remoteSourceOfServer(server),
          library: KomgaLibraryRepository(session, sync),
          reader: KomgaReaderRepository(session, sync),
          collections: KomgaCollectionsRepository(session, sync),
          readStatus: KomgaReadStatusRepository(session, sync),
        );
      }

      ref.onDispose(() {
        for (final s in extraSessions) {
          s.close();
        }
      });

      return SourceRegistry(localBundle: local, remoteBundles: remotes);
    });
