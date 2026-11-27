import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 当前激活内容源的稳定分区键（本机为 `'local://device'`，Komga 为规范化 `baseUrl`）。
final Provider<String> activeServerKeyProvider = Provider<String>((Ref ref) {
  return ref.watch(activeSourceProvider).sourceKey;
});

/// 指定内容源分区下置顶的系列 id（按 `sourceKey` 物理隔离，ARC-10 Drift 表更新流自动刷新）。
final pinnedSeriesIdsForSourceProvider =
    FutureProvider.family<List<String>, String>((Ref ref, String sourceKey) {
      if (sourceKey.isEmpty) {
        return Future<List<String>>.value(const <String>[]);
      }
      final db = ref.watch(progressDatabaseProvider);
      final sub = db.pinnedSeriesUpdates().listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return db.pinnedSeries(sourceKey);
    });

/// 当前激活内容源下置顶的系列 id。
final FutureProvider<List<String>> pinnedSeriesIdsProvider =
    FutureProvider<List<String>>((Ref ref) {
      final serverKey = ref.watch(activeServerKeyProvider);
      return ref.watch(pinnedSeriesIdsForSourceProvider(serverKey).future);
    });

/// 指定内容源下置顶系列的完整元数据：按 `sourceKey` 路由到对应源的书库查询。
final pinnedSeriesForSourceProvider =
    FutureProvider.family<List<Series>, String>((
      Ref ref,
      String sourceKey,
    ) async {
      final ids = await ref.watch(
        pinnedSeriesIdsForSourceProvider(sourceKey).future,
      );
      if (ids.isEmpty) return const <Series>[];
      final repository = ref.watch(
        libraryRepositoryForSourceProvider(sourceKey),
      );
      final result = <Series>[];
      for (final id in ids) {
        final series = await repository.seriesById(id);
        if (series != null) result.add(series);
      }
      return result;
    });

/// 当前激活内容源置顶系列的完整元数据：上游 [pinnedSeriesIdsProvider] 流更新后自动重建。
final FutureProvider<List<Series>> pinnedSeriesProvider =
    FutureProvider<List<Series>>((Ref ref) {
      final serverKey = ref.watch(activeServerKeyProvider);
      return ref.watch(pinnedSeriesForSourceProvider(serverKey).future);
    });

/// 置顶/取消置顶与备份还原（数据库表变更后由 Drift 流自动推送，无需手工 invalidate）。
final Provider<PinnedSeriesController> pinnedSeriesControllerProvider =
    Provider<PinnedSeriesController>((Ref ref) {
      return PinnedSeriesController(ref);
    });

class PinnedSeriesController {
  PinnedSeriesController(this._ref);

  final Ref _ref;

  String _resolveKey(String? sourceKey) =>
      sourceKey ?? _ref.read(activeServerKeyProvider);

  Future<List<String>> currentIds({String? sourceKey}) async {
    final serverKey = _resolveKey(sourceKey);
    if (serverKey.isEmpty) return const <String>[];
    return _ref.read(progressDatabaseProvider).pinnedSeries(serverKey);
  }

  Future<void> toggle(
    String seriesId, {
    required bool pinned,
    String? sourceKey,
  }) async {
    final serverKey = _resolveKey(sourceKey);
    if (serverKey.isEmpty) return;
    await _ref
        .read(progressDatabaseProvider)
        .setPinned(serverId: serverKey, seriesId: seriesId, pinned: pinned);
  }

  Future<void> replaceAll(List<String> seriesIds, {String? sourceKey}) async {
    final serverKey = _resolveKey(sourceKey);
    if (serverKey.isEmpty) return;
    await _ref
        .read(progressDatabaseProvider)
        .replacePinnedSeries(serverKey, seriesIds);
  }
}
