import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/local/local_collections_repository.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_library_repository.dart';
import 'package:yomu/src/data/local/local_read_status_repository.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress_sink.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/archive_password_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 单一内容源完整装配单元（领域仓库 + 下载服务 + 进度上传端口 + 源能力描述符）。
///
/// 后续扩展 Kavita / OPDS 时只需实现对应的 [RemoteSourcePlugin] 挂入
/// [remoteSourcePluginsProvider]，上层 UI、同步服务与状态机零改动。
final class SourceBundle {
  const SourceBundle({
    required this.source,
    required this.library,
    required this.reader,
    required this.collections,
    required this.readStatus,
    this.download = const NoopDownloadService(),
    this.progressSink = const NoopProgressSink(),
  });

  final ContentSource source;
  final LibraryRepository library;
  final ReaderRepository reader;
  final CollectionsRepository collections;
  final ReadStatusRepository readStatus;
  final DownloadService download;
  final ProgressSink progressSink;
}

/// 远程协议插件契约（P1-4）：将进度上传端口与完整 [SourceBundle] 拆分为两阶段构建，
/// 确保 `progressSyncProvider` 仅依赖轻量进度端口而不与需要叠加本地进度的仓库产生环依赖。
abstract interface class RemoteSourcePlugin {
  /// 构建远程进度上传端口；不支持远程同步的协议返回 [NoopProgressSink]。
  ProgressSink? buildProgressSink(Ref ref, StoredServer server);

  /// 构建该服务器的完整 [SourceBundle]（含已装配好的 [progressSink]）。
  SourceBundle? buildBundle(
    Ref ref,
    StoredServer server,
    ProgressSink progressSink,
  );
}

final class _KomgaSourcePlugin implements RemoteSourcePlugin {
  const _KomgaSourcePlugin();

  @override
  ProgressSink? buildProgressSink(Ref ref, StoredServer server) {
    final session = ref.watch(komgaSessionForServerProvider(server.id));
    if (session == null) return null;
    return KomgaProgressSink(session);
  }

  @override
  SourceBundle? buildBundle(
    Ref ref,
    StoredServer server,
    ProgressSink progressSink,
  ) {
    final session = ref.watch(komgaSessionForServerProvider(server.id));
    if (session == null) return null;
    final sync = ref.watch(progressSyncProvider);
    final cacheDb = ref.watch(httpCacheDatabaseProvider);
    return SourceBundle(
      source: remoteSourceOfServer(server),
      library: KomgaLibraryRepository(session, sync),
      reader: KomgaReaderRepository(session, sync),
      collections: KomgaCollectionsRepository(session, sync),
      readStatus: KomgaReadStatusRepository(session, sync),
      download: KomgaDownloadService.forSession(session, cacheDb),
      progressSink: progressSink,
    );
  }
}

/// 按 [SourceKind] 注册的远程内容源协议插件表（P1-4）。
final Provider<Map<SourceKind, RemoteSourcePlugin>>
remoteSourcePluginsProvider = Provider<Map<SourceKind, RemoteSourcePlugin>>(
  (Ref ref) => const <SourceKind, RemoteSourcePlugin>{
    SourceKind.komga: _KomgaSourcePlugin(),
  },
);

/// 轻量内容源元数据表（本机 + 已保存/已连接的远程源描述符），不触发任何仓库或会话创建。
final Provider<Map<String, ContentSource>> contentSourceDescriptorsProvider =
    Provider<Map<String, ContentSource>>((Ref ref) {
      final connectedServer = ref.watch(
        sessionProvider.select(
          (SessionState state) =>
              state is SessionConnected ? state.server : null,
        ),
      );
      final savedServers =
          ref.watch(serverListProvider).value ?? const <StoredServer>[];

      return Map<String, ContentSource>.unmodifiable(<String, ContentSource>{
        kLocalSourceKey: const LocalContentSource(),
        for (final s in savedServers) s.id: remoteSourceOfServer(s),
        if (connectedServer != null)
          connectedServer.id: remoteSourceOfServer(connectedServer),
      });
    });

/// 按 `sourceKey` 懒解析远程进度上传端口（由 [remoteSourcePluginsProvider] 按协议分派）。
final progressSinkForSourceProvider = Provider.family<ProgressSink?, String>((
  Ref ref,
  String sourceKey,
) {
  if (sourceKey.isEmpty) return null;
  if (isLocalSourceKey(sourceKey)) return const NoopProgressSink();
  final server = ref.watch(storedServerByIdProvider(sourceKey));
  if (server == null) return null;
  final plugin = ref.watch(remoteSourcePluginsProvider)[server.kind];
  if (plugin == null) return null;
  return plugin.buildProgressSink(ref, server);
});

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

  /// 纯元数据查询远程源描述符：不触发任何仓库或网络连接池的懒加载构建（P3）。
  RemoteContentSource? remoteSourceOrNull(String sourceKey) =>
      _remoteSources[sourceKey];

  /// 按 `sourceKey` 查询对应装配单元；空串或未知远程 `sourceKey` 返回 `null` 而非回退本机。
  SourceBundle? bundleOrNull(String sourceKey) {
    if (sourceKey.isEmpty) return null;
    if (isLocalSourceKey(sourceKey)) return localBundle;
    if (!_remoteSources.containsKey(sourceKey)) return null;
    return _resolveRemote(sourceKey);
  }

  /// 按 `sourceKey` 获取对应装配单元；空串或未知远程 `sourceKey` 抛 [StateError]。
  SourceBundle bundleFor(String sourceKey) {
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
        passwordStore: ref.watch(archivePasswordStoreProvider),
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
      kind: server.kind,
      capabilities: SourceCapabilities.forKind(server.kind),
    );

/// 单台远程服务器的懒加载 [SourceBundle]（P1-3 / P1-4）。
///
/// 仅在访问该服务器时按 `server.kind` 分派创建其会话与仓库实例（含封面内存 LRU），
/// 切换或增删其他服务器不会销毁重建本服务器的缓存。
final remoteSourceBundleProvider = Provider.family<SourceBundle?, String>((
  Ref ref,
  String serverId,
) {
  final server = ref.watch(storedServerByIdProvider(serverId));
  if (server == null) return null;
  final plugin = ref.watch(remoteSourcePluginsProvider)[server.kind];
  if (plugin == null) return null;
  final sink = ref.watch(progressSinkForSourceProvider(server.id));
  if (sink == null) return null;
  return plugin.buildBundle(ref, server, sink);
});

/// 全局多源注册表：自动汇聚常驻本机源 + 已保存/已连接的远程源描述符，
/// 远程 `SourceBundle` 经 [remoteSourceBundleProvider] 按需懒创建并长驻缓存。
final Provider<SourceRegistry> sourceRegistryProvider =
    Provider<SourceRegistry>((Ref ref) {
      final local = ref.watch(localSourceBundleProvider);
      final descriptors = ref.watch(contentSourceDescriptorsProvider);
      final remoteSources = <RemoteContentSource>[
        for (final source in descriptors.values)
          if (source is RemoteContentSource) source,
      ];

      return SourceRegistry.lazy(
        localBundle: local,
        remoteSources: remoteSources,
        resolveRemote: (String sourceKey) =>
            ref.read(remoteSourceBundleProvider(sourceKey)),
      );
    });
