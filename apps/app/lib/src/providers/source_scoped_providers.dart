import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/missing_source_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';

/// 按显式 `sourceKey` 解析内容源静态能力位（P1-1）。
///
/// UI 与业务层一律基于 [SourceCapabilities] 判断是否展示下载、离线标识、本地编辑等能力，
/// 绝不嗅探实体 ID 前缀；未知或已移除的远程 `sourceKey` 统一降级为 [SourceCapabilities.none]。
final sourceCapabilitiesForKeyProvider =
    Provider.family<SourceCapabilities, String?>((Ref ref, String? sourceKey) {
      if (sourceKey != null && sourceKey.isNotEmpty) {
        final registry = ref.watch(sourceRegistryProvider);
        if (isLocalSourceKey(sourceKey)) {
          return registry.localBundle.source.capabilities;
        }
        for (final source in registry.sources) {
          if (source.sourceKey == sourceKey) return source.capabilities;
        }
        return SourceCapabilities.none;
      }
      return ref.watch(activeSourceProvider).capabilities;
    });

/// 根据实体携带的 `entitySourceKey` 与当前作用域 `scopedSourceKey` 解析能力位。
///
/// 有显式作用域时优先按 `scopedSourceKey` 解析，否则按实体自身的 `entitySourceKey` 解析。
final sourceCapabilitiesForItemProvider =
    Provider.family<
      SourceCapabilities,
      ({String? scopedSourceKey, String entitySourceKey})
    >((Ref ref, ({String? scopedSourceKey, String entitySourceKey}) query) {
      final scoped = query.scopedSourceKey;
      final targetKey = (scoped != null && scoped.isNotEmpty)
          ? scoped
          : query.entitySourceKey;
      return ref.watch(sourceCapabilitiesForKeyProvider(targetKey));
    });

/// 按显式 `sourceKey` 解析 [LibraryRepository]。
///
/// `sourceKey` 为空时返回当前激活源的 [libraryRepositoryProvider]；
/// 否则直接经 [sourceRegistryProvider] 精确路由，未知源返回 [MissingSourceRepository]。
final libraryRepositoryForSourceProvider =
    Provider.family<LibraryRepository, String?>((Ref ref, String? sourceKey) {
      if (sourceKey == null || sourceKey.isEmpty) {
        return ref.watch(libraryRepositoryProvider);
      }
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.library ??
          MissingSourceRepository(sourceKey);
    });

/// 按显式 `sourceKey` 解析 [ReaderRepository]。
final readerRepositoryForSourceProvider =
    Provider.family<ReaderRepository, String?>((Ref ref, String? sourceKey) {
      if (sourceKey == null || sourceKey.isEmpty) {
        return ref.watch(readerRepositoryProvider);
      }
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.reader ??
          MissingSourceRepository(sourceKey);
    });

/// 按显式 `sourceKey` 解析 [CollectionsRepository]。
final collectionsRepositoryForSourceProvider =
    Provider.family<CollectionsRepository, String?>((
      Ref ref,
      String? sourceKey,
    ) {
      if (sourceKey == null || sourceKey.isEmpty) {
        return ref.watch(collectionsRepositoryProvider);
      }
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.collections ??
          MissingSourceRepository(sourceKey);
    });

/// 按显式 `sourceKey` 解析 [ReadStatusRepository]。
final readStatusRepositoryForSourceProvider =
    Provider.family<ReadStatusRepository, String?>((
      Ref ref,
      String? sourceKey,
    ) {
      if (sourceKey == null || sourceKey.isEmpty) {
        return ref.watch(readStatusRepositoryProvider);
      }
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.readStatus ??
          MissingSourceRepository(sourceKey);
    });
