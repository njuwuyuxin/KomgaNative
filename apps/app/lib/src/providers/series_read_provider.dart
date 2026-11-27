import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';

/// 阅读状态变更后的统一跨模块联动刷新钩子（ARC-10）。
void invalidateAfterReadStatusChange(
  Ref ref, {
  String? seriesId,
  String? sourceKey,
}) {
  if (seriesId != null && sourceKey != null) {
    ref.invalidate(
      seriesDetailProvider((sourceKey: sourceKey, seriesId: seriesId)),
    );
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
    required String sourceKey,
    Book? completedBook,
  }) async {
    final wrote = await flushProgress();
    if (!wrote || _disposed) return;

    if (completedBook != null) {
      await _maybeAutoDeleteCompleted(completedBook, sourceKey: sourceKey);
      if (_disposed) return;
    }

    final sync = _ref.read(progressSyncProvider);
    // 第一阶段：本地 Outbox 已写入，立即刷新支持本地叠加的列表与继续阅读。
    _ref.invalidate(readerBookProvider((sourceKey: sourceKey, bookId: bookId)));
    invalidateAfterReadStatusChange(
      _ref,
      seriesId: seriesId,
      sourceKey: sourceKey,
    );

    // 第二阶段：等服务端 PATCH 完成后，再刷一次依赖服务端聚合计数的系列详情与书架。
    await sync.flush(scope: sourceKey);
    if (_disposed) return;
    if (seriesId != null) {
      _ref.invalidate(
        seriesDetailProvider((sourceKey: sourceKey, seriesId: seriesId)),
      );
    } else {
      _ref.invalidate(seriesDetailProvider);
    }
    _ref.invalidate(recentSeriesProvider);
    _ref.invalidate(libraryShelfProvider);
    _ref.invalidate(collectionSeriesProvider);
    _ref.read(readStatusEpochProvider.notifier).bump();
  }

  /// 自然读完最后一页退出时按"读完自动删除"策略清理已下载副本。
  Future<void> _maybeAutoDeleteCompleted(
    Book book, {
    required String sourceKey,
  }) async {
    try {
      final policy = _ref.read(downloadPolicyProvider).value;
      if (policy == null || !policy.autoDeleteRead) return;
      final record = await _ref.read(
        downloadedForSourceProvider((sourceKey: sourceKey, bookId: book.id))
            .future,
      );
      if (record == null || _disposed) return;
      await _ref
          .read(downloadsProvider.notifier)
          .delete(book.withSource(sourceKey));
    } on Object catch (error) {
      // 自动清理属于增强行为，失败不影响进度结算。
      debugPrint(
        'ReaderProgressCommitter: auto-delete completed download failed: $error',
      );
    }
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

  Future<void> setRead(
    String seriesId, {
    required bool read,
    String? sourceKey,
  }) async {
    if (state.contains(seriesId)) return;
    state = <String>{...state, seriesId};
    try {
      final key = readEffectiveSourceKey(ref, sourceKey);
      await ref
          .read(readStatusRepositoryForSourceProvider(key))
          .setSeriesRead(seriesId, read: read);
      if (_disposed) return;
      invalidateAfterReadStatusChange(
        ref,
        seriesId: seriesId,
        sourceKey: sourceKey,
      );
    } finally {
      if (!_disposed) state = <String>{...state}..remove(seriesId);
    }
  }
}

final seriesReadProvider = NotifierProvider<SeriesReadController, Set<String>>(
  SeriesReadController.new,
);
