import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_providers.dart';

/// 阅读状态变更后的统一跨模块联动刷新钩子（ARC-10）。
void invalidateAfterReadStatusChange(Ref ref, {String? seriesId}) {
  if (seriesId != null) {
    ref.invalidate(seriesDetailProvider(seriesId));
  } else {
    ref.invalidate(seriesDetailProvider);
  }
  ref.invalidate(seriesBooksProvider);
  ref.invalidate(readListBooksProvider);
  ref.invalidate(collectionSeriesProvider);
  ref.invalidate(ondeckProvider);
  ref.invalidate(recentSeriesProvider);
  ref.invalidate(libraryShelfProvider);
  ref.invalidate(pinnedSeriesProvider);
  ref.read(readStatusEpochProvider.notifier).bump();
}

/// 阅读器退出/切书时的进度落盘与跨页联动刷新器。
///
/// 挂在根容器上并在 `ReaderScreen.initState` 里预取：阅读器弹出/销毁时 Widget 自身的
/// `WidgetRef` 已失效，通过容器级 `Ref`（带 `_disposed` 保护）仍可安全完成收尾与失效通知。
class ReaderProgressCommitter {
  ReaderProgressCommitter(this._ref) {
    _ref.onDispose(() => _disposed = true);
  }

  final Ref _ref;
  bool _disposed = false;

  Future<void> settle({
    required Future<bool> Function() flushProgress,
    required String bookId,
    String? seriesId,
  }) async {
    final wrote = await flushProgress();
    if (!wrote || _disposed) return;

    final sync = _ref.read(progressSyncProvider);
    // 第一阶段：本地 Outbox 已写入，立即刷新支持本地叠加的列表与继续阅读。
    _ref.invalidate(readerBookProvider(bookId));
    invalidateAfterReadStatusChange(_ref, seriesId: seriesId);

    // 第二阶段：等服务端 PATCH 完成后，再刷一次依赖服务端聚合计数的系列详情与书架。
    await sync.flush();
    if (_disposed) return;
    if (seriesId != null) {
      _ref.invalidate(seriesDetailProvider(seriesId));
    } else {
      _ref.invalidate(seriesDetailProvider);
    }
    _ref.invalidate(recentSeriesProvider);
    _ref.invalidate(libraryShelfProvider);
    _ref.invalidate(collectionSeriesProvider);
    _ref.read(readStatusEpochProvider.notifier).bump();
  }
}

final Provider<ReaderProgressCommitter> readerProgressCommitterProvider =
    Provider<ReaderProgressCommitter>(ReaderProgressCommitter.new);

/// 系列级阅读状态写入（标记全部已读 / 未读）。
class SeriesReadController extends Notifier<Set<String>> {
  bool _disposed = false;

  @override
  Set<String> build() {
    ref.onDispose(() => _disposed = true);
    return const <String>{};
  }

  Future<void> setRead(String seriesId, {required bool read}) async {
    if (state.contains(seriesId)) return;
    state = <String>{...state, seriesId};
    try {
      await ref
          .read(readStatusRepositoryProvider)
          .setSeriesRead(seriesId, read: read);
      if (_disposed) return;
      invalidateAfterReadStatusChange(ref, seriesId: seriesId);
    } finally {
      if (!_disposed) state = <String>{...state}..remove(seriesId);
    }
  }
}

final seriesReadProvider = NotifierProvider<SeriesReadController, Set<String>>(
  SeriesReadController.new,
);
