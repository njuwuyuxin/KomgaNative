import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/missing_source_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 解析显式路由键：`sourceKey == null` 表示显式使用当前激活源；
/// 传入空串 `''` 时原样透传（绝不静默当成本机或当前激活源，由下游暴露未知源错误）。
String resolveEffectiveSourceKey(Ref ref, String? sourceKey) =>
    sourceKey ?? ref.watch(activeSourceProvider).sourceKey;

/// 与 [resolveEffectiveSourceKey] 语义相同，供命令式 `ref.read` 路径使用。
String readEffectiveSourceKey(Ref ref, String? sourceKey) =>
    sourceKey ?? ref.read(activeSourceProvider).sourceKey;

/// 按非空 `sourceKey` 解析内容源静态能力位（P1-1）。
///
/// 空串、未知或已移除的远程 `sourceKey` 统一降级为 [SourceCapabilities.none]。
final sourceCapabilitiesForKeyProvider =
    Provider.family<SourceCapabilities, String>((Ref ref, String sourceKey) {
      if (sourceKey.isEmpty) return SourceCapabilities.none;
      final registry = ref.watch(sourceRegistryProvider);
      if (isLocalSourceKey(sourceKey)) {
        return registry.localBundle.source.capabilities;
      }
      for (final source in registry.sources) {
        if (source.sourceKey == sourceKey) return source.capabilities;
      }
      return SourceCapabilities.none;
    });

/// 根据实体携带的 `entitySourceKey` 与当前作用域 `scopedSourceKey` 解析能力位。
///
/// 有显式作用域时优先按 `scopedSourceKey` 解析，否则按实体自身的 `entitySourceKey` 解析。
final sourceCapabilitiesForItemProvider =
    Provider.family<
      SourceCapabilities,
      ({String? scopedSourceKey, String entitySourceKey})
    >((Ref ref, ({String? scopedSourceKey, String entitySourceKey}) query) {
      final targetKey = query.scopedSourceKey ?? query.entitySourceKey;
      return ref.watch(sourceCapabilitiesForKeyProvider(targetKey));
    });

/// 按非空 `sourceKey` 精确解析 [LibraryRepository]；空串或未知源返回 [MissingSourceRepository]。
final libraryRepositoryForSourceProvider =
    Provider.family<LibraryRepository, String>((Ref ref, String sourceKey) {
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.library ??
          MissingSourceRepository(sourceKey);
    });

/// 按非空 `sourceKey` 精确解析 [ReaderRepository]；空串或未知源返回 [MissingSourceRepository]。
final readerRepositoryForSourceProvider =
    Provider.family<ReaderRepository, String>((Ref ref, String sourceKey) {
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.reader ??
          MissingSourceRepository(sourceKey);
    });

/// 按非空 `sourceKey` 精确解析 [CollectionsRepository]；空串或未知源返回 [MissingSourceRepository]。
final collectionsRepositoryForSourceProvider =
    Provider.family<CollectionsRepository, String>((Ref ref, String sourceKey) {
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.collections ??
          MissingSourceRepository(sourceKey);
    });

/// 按非空 `sourceKey` 精确解析 [ReadStatusRepository]；空串或未知源返回 [MissingSourceRepository]。
final readStatusRepositoryForSourceProvider =
    Provider.family<ReadStatusRepository, String>((Ref ref, String sourceKey) {
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.readStatus ??
          MissingSourceRepository(sourceKey);
    });
