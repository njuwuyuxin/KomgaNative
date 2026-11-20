import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';

/// 当前服务器的稳定标识（LIB-02）。
///
/// 用 baseUrl 而不是账号：同一台机器可能连过多个 Komga，置顶不能串。
/// 没有连接时返回空串，下游读到空 id 列表 = 没有置顶。
final Provider<String> activeServerKeyProvider = Provider<String>((Ref ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionConnected ? session.server.address.baseUrl : '';
});

/// 这台服务器上置顶的系列 id（最近的在前，存储于用户库 `komga_native.sqlite`）。
final FutureProvider<List<String>> pinnedSeriesIdsProvider =
    FutureProvider<List<String>>((Ref ref) {
      final serverKey = ref.watch(activeServerKeyProvider);
      if (serverKey.isEmpty) {
        return Future<List<String>>.value(const <String>[]);
      }
      return ref.watch(progressDatabaseProvider).pinnedSeries(serverKey);
    });

/// 置顶系列的完整元数据：按 id 逐本取（通常只有个位数），失败的跳过。
final FutureProvider<List<Series>> pinnedSeriesProvider =
    FutureProvider<List<Series>>((Ref ref) async {
      final ids = await ref.watch(pinnedSeriesIdsProvider.future);
      if (ids.isEmpty) return const <Series>[];
      final repository = ref.watch(libraryRepositoryProvider);
      final result = <Series>[];
      for (final id in ids) {
        final series = await repository.seriesById(id);
        if (series != null) result.add(series);
      }
      return result;
    });

/// 置顶/取消置顶与备份还原。
final Provider<PinnedSeriesController> pinnedSeriesControllerProvider =
    Provider<PinnedSeriesController>((Ref ref) {
      return PinnedSeriesController(ref);
    });

class PinnedSeriesController {
  PinnedSeriesController(this._ref);

  final Ref _ref;

  Future<List<String>> currentIds() async {
    final serverKey = _ref.read(activeServerKeyProvider);
    if (serverKey.isEmpty) return const <String>[];
    return _ref.read(progressDatabaseProvider).pinnedSeries(serverKey);
  }

  Future<void> toggle(String seriesId, {required bool pinned}) async {
    final serverKey = _ref.read(activeServerKeyProvider);
    if (serverKey.isEmpty) return;
    await _ref
        .read(progressDatabaseProvider)
        .setPinned(serverId: serverKey, seriesId: seriesId, pinned: pinned);
    _ref.invalidate(pinnedSeriesIdsProvider);
    _ref.invalidate(pinnedSeriesProvider);
  }

  Future<void> replaceAll(List<String> seriesIds) async {
    final serverKey = _ref.read(activeServerKeyProvider);
    if (serverKey.isEmpty) return;
    await _ref
        .read(progressDatabaseProvider)
        .replacePinnedSeries(serverKey, seriesIds);
    _ref.invalidate(pinnedSeriesIdsProvider);
    _ref.invalidate(pinnedSeriesProvider);
  }
}
