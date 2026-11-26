import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/download/download_service.dart';
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

/// 单一内容源完整装配单元（五大领域能力 + 源能力描述符）。
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
    this.download = const NoopDownloadService(),
  });

  final ContentSource source;
  final LibraryRepository library;
  final ReaderRepository reader;
  final CollectionsRepository collections;
  final ReadStatusRepository readStatus;
  final DownloadService download;
}

/// 多源插件注册表：按 `sourceKey` 懒解析对应的 [SourceBundle]（P1-3）。
///
/// 未知 `sourceKey` 绝不静默回退到本机书库：
/// - [bundleOrNull] 返回 `null` 供容错调用方显式降级；
/// - [bundleFor] 抛出 [StateError] 暴露非法或已删除的源引用。
final class SourceRegistry {
  SourceRegistry({
    required this.localBundle,
    required Map<String, SourceBundle> remoteBundles,
  }) : _remoteSources = Map<String, RemoteContentSource>.unmodifiable(
         <String, RemoteContentSource>{
           for (final entry in remoteBundles.entries)
             if (entry.value.source is RemoteContentSource)
               entry.key: entry.value.source as RemoteContentSource,
         },
       ),
       _resolveRemote = ((String key) => remoteBundles[key]);

  /// 懒加载构造：仅注册轻量 [RemoteContentSource] 列表，按需解析具体 [SourceBundle]。
  ///
  /// 生命周期约束：本注册表不会订阅每台远程源 [SourceBundle] 的内部变更。
  /// 当单台服务器的会话或凭据重建（如更换 API Key）导致底层 bundle 重建时，
  /// 已持有本 `SourceRegistry` 引用的调用方**不会**自动刷新，需等待
  /// `serverListProvider` / `sessionProvider` 变化触发注册表整体重建，或直接监听
  /// `remoteSourceBundleProvider(sourceKey)`。
  SourceRegistry.lazy({
    required this.localBundle,
    required List<RemoteContentSource> remoteSources,
    required SourceBundle? Function(String sourceKey) resolveRemote,
  }) : _remoteSources = Map<String, RemoteContentSource>.unmodifiable(
         <String, RemoteContentSource>{
           for (final source in remoteSources) source.sourceKey: source,
         },
       ),
       _resolveRemote = resolveRemote;

  final SourceBundle localBundle;
  final Map<String, RemoteContentSource> _remoteSources;
  final SourceBundle? Function(String sourceKey) _resolveRemote;

  List<ContentSource> get sources => <ContentSource>[
    localBundle.source,
    ..._remoteSources.values,
  ];

  Iterable<SourceBundle> get remoteBundles sync* {
    for (final key in _remoteSources.keys) {
      final bundle = _resolveRemote(key);
      if (bundle != null) yield bundle;
    }
  }

  bool get hasRemoteSources => _remoteSources.isNotEmpty;

  /// 按 `sourceKey` 查询对应装配单元；未知远程 `sourceKey` 返回 `null` 而非回退本机。
  SourceBundle? bundleOrNull(String? sourceKey) {
    if (sourceKey == null || isLocalSourceKey(sourceKey)) {
      return localBundle;
    }
    if (!_remoteSources.containsKey(sourceKey)) return null;
    return _resolveRemote(sourceKey);
  }

  /// 按 `sourceKey` 获取对应装配单元；未知远程 `sourceKey` 抛 [StateError]。
  SourceBundle bundleFor(String? sourceKey) {
    final bundle = bundleOrNull(sourceKey);
    if (bundle == null) {
      throw StateError('Unknown content source: $sourceKey');
    }
    return bundle;
  }

  SourceBundle? remoteBundleOrNull(String sourceKey) {
    if (!_remoteSources.containsKey(sourceKey)) return null;
    return _resolveRemote(sourceKey);
  }
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

/// 单台远程服务器的懒加载 [SourceBundle]（P1-3）。
///
/// 仅在访问该服务器时创建其会话与仓库实例（含封面内存 LRU），
/// 切换或增删其他服务器不会销毁重建本服务器的缓存。
final remoteSourceBundleProvider = Provider.family<SourceBundle?, String>((
  Ref ref,
  String serverId,
) {
  final server = ref.watch(storedServerByIdProvider(serverId));
  final session = ref.watch(komgaSessionForServerProvider(serverId));
  if (server == null || session == null) return null;
  final sync = ref.watch(progressSyncProvider);
  final cacheDb = ref.watch(httpCacheDatabaseProvider);
  return SourceBundle(
    source: remoteSourceOfServer(server),
    library: KomgaLibraryRepository(session, sync),
    reader: KomgaReaderRepository(session, sync),
    collections: KomgaCollectionsRepository(session, sync),
    readStatus: KomgaReadStatusRepository(session, sync),
    download: KomgaDownloadService.forSession(session, cacheDb),
  );
});

/// 全局多源注册表：自动汇聚常驻本机源 + 已保存/已连接的远程源描述符，
/// 远程 `SourceBundle` 经 [remoteSourceBundleProvider] 按需懒创建并长驻缓存。
///
/// 刷新约束：`resolveRemote` 内部使用 `ref.read(remoteSourceBundleProvider(sourceKey))`，
/// 刻意不建立对单台远程 bundle 的依赖，以免单服访问/失效拖累整张注册表重建。
/// 因此仅当 `serverListProvider` 或 `sessionProvider` 变更时才会重建注册表并通知下游；
/// 若调用方需响应单台服务器的凭据/会话热更新，应直接 `ref.watch(remoteSourceBundleProvider(key))`
/// 并确保凭据更新路径同步刷新 `serverListProvider`。
final Provider<SourceRegistry> sourceRegistryProvider =
    Provider<SourceRegistry>((Ref ref) {
      final local = ref.watch(localSourceBundleProvider);
      final connectedServer = ref.watch(
        sessionProvider.select(
          (SessionState state) =>
              state is SessionConnected ? state.server : null,
        ),
      );
      final savedServers =
          ref.watch(serverListProvider).value ?? const <StoredServer>[];

      final remoteSourcesById = <String, RemoteContentSource>{
        for (final s in savedServers) s.id: remoteSourceOfServer(s),
        if (connectedServer != null)
          connectedServer.id: remoteSourceOfServer(connectedServer),
      };

      return SourceRegistry.lazy(
        localBundle: local,
        remoteSources: remoteSourcesById.values.toList(growable: false),
        resolveRemote: (String sourceKey) =>
            ref.read(remoteSourceBundleProvider(sourceKey)),
      );
    });
