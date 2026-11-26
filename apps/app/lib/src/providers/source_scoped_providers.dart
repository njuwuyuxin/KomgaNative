import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';

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
      return ref.watch(sourceRegistryProvider).bundleFor(sourceKey).library;
    });

/// 按显式 `sourceKey` 解析 [ReaderRepository]。
final readerRepositoryForSourceProvider =
    Provider.family<ReaderRepository, String?>((Ref ref, String? sourceKey) {
      final primary = ref.watch(readerRepositoryProvider);
      if (sourceKey == null || sourceKey.isEmpty) return primary;
      final activeBundle = ref.watch(activeSourceBundleProvider);
      if (!identical(primary, activeBundle.reader)) return primary;
      if (sourceKey == activeBundle.source.sourceKey) return primary;
      return ref.watch(sourceRegistryProvider).bundleFor(sourceKey).reader;
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
      return ref.watch(sourceRegistryProvider).bundleFor(sourceKey).collections;
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
      return ref.watch(sourceRegistryProvider).bundleFor(sourceKey).readStatus;
    });
