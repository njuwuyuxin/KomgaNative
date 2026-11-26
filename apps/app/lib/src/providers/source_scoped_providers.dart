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
/// 绝不嗅探实体 ID 前缀。
final sourceCapabilitiesForKeyProvider =
    Provider.family<SourceCapabilities, String?>((Ref ref, String? sourceKey) {
      if (sourceKey != null && sourceKey.isNotEmpty) {
        if (isLocalSourceKey(sourceKey)) {
          return SourceCapabilities.local;
        }
        final registry = ref.watch(sourceRegistryProvider);
        for (final source in registry.sources) {
          if (source.sourceKey == sourceKey) return source.capabilities;
        }
        return SourceCapabilities.komga;
      }
      final active = ref.watch(activeSourceProvider);
      if (active.isCloud) return active.capabilities;
      // 兼容未配置远程服务器、仅通过 override 注入假仓库的单测与黄金图。
      final activeBundle = ref.watch(activeSourceBundleProvider);
      final primaryLibrary = ref.watch(libraryRepositoryProvider);
      final primaryReader = ref.watch(readerRepositoryProvider);
      if (!identical(primaryLibrary, activeBundle.library) ||
          !identical(primaryReader, activeBundle.reader)) {
        return SourceCapabilities.komga;
      }
      return active.capabilities;
    });

/// 根据实体携带的 `entitySourceKey` 与当前作用域 `scopedSourceKey` 解析能力位。
///
/// - 有显式作用域或实体为云端源时直接按其 `sourceKey` 解析；
/// - 生产环境无覆写仓库时直接按实体 `sourceKey` 解析（确保跨源列表中的本机书仍使用本机能力）；
/// - 仅在单测通过 override 注入假仓库且未指定作用域时，按 [sourceCapabilitiesForKeyProvider] 回退。
final sourceCapabilitiesForItemProvider =
    Provider.family<
      SourceCapabilities,
      ({String? scopedSourceKey, String entitySourceKey})
    >((Ref ref, ({String? scopedSourceKey, String entitySourceKey}) query) {
      final scoped = query.scopedSourceKey;
      if (scoped != null && scoped.isNotEmpty) {
        return ref.watch(sourceCapabilitiesForKeyProvider(scoped));
      }
      if (!isLocalSourceKey(query.entitySourceKey)) {
        return ref.watch(
          sourceCapabilitiesForKeyProvider(query.entitySourceKey),
        );
      }
      final activeBundle = ref.watch(activeSourceBundleProvider);
      final primaryLibrary = ref.watch(libraryRepositoryProvider);
      if (!identical(primaryLibrary, activeBundle.library)) {
        return ref.watch(sourceCapabilitiesForKeyProvider(null));
      }
      return ref.watch(sourceCapabilitiesForKeyProvider(query.entitySourceKey));
    });

/// 按显式 `sourceKey` 解析 [LibraryRepository]。
///
/// - `sourceKey` 为空或等于当前激活源时返回 [libraryRepositoryProvider]；
/// - 若单测显式 override 了 [libraryRepositoryProvider]（不再与激活源 bundle 相同），
///   保留被测 fake 不被绕过；
/// - 否则通过 [sourceRegistryProvider] 按 `sourceKey` 精确路由，不依赖嵌套 `ProviderScope`。
final libraryRepositoryForSourceProvider =
    Provider.family<LibraryRepository, String?>((Ref ref, String? sourceKey) {
      final primary = ref.watch(libraryRepositoryProvider);
      if (sourceKey == null || sourceKey.isEmpty) return primary;
      final activeBundle = ref.watch(activeSourceBundleProvider);
      if (!identical(primary, activeBundle.library)) return primary;
      if (sourceKey == activeBundle.source.sourceKey) return primary;
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.library ??
          MissingSourceRepository(sourceKey);
    });

/// 按显式 `sourceKey` 解析 [ReaderRepository]。
final readerRepositoryForSourceProvider =
    Provider.family<ReaderRepository, String?>((Ref ref, String? sourceKey) {
      final primary = ref.watch(readerRepositoryProvider);
      if (sourceKey == null || sourceKey.isEmpty) return primary;
      final activeBundle = ref.watch(activeSourceBundleProvider);
      if (!identical(primary, activeBundle.reader)) return primary;
      if (sourceKey == activeBundle.source.sourceKey) return primary;
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
      final primary = ref.watch(collectionsRepositoryProvider);
      if (sourceKey == null || sourceKey.isEmpty) return primary;
      final activeBundle = ref.watch(activeSourceBundleProvider);
      if (!identical(primary, activeBundle.collections)) return primary;
      if (sourceKey == activeBundle.source.sourceKey) return primary;
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
      final primary = ref.watch(readStatusRepositoryProvider);
      if (sourceKey == null || sourceKey.isEmpty) return primary;
      final activeBundle = ref.watch(activeSourceBundleProvider);
      if (!identical(primary, activeBundle.readStatus)) return primary;
      if (sourceKey == activeBundle.source.sourceKey) return primary;
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.readStatus ??
          MissingSourceRepository(sourceKey);
    });
