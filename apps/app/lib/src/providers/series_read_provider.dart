import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';

/// 阅读状态变更后的统一跨模块联动刷新钩子（ARC-10）。
void invalidateAfterReadStatusChange(Ref ref, {String? seriesId}) {
  if (seriesId != null) {
    ref.invalidate(seriesDetailProvider(seriesId));
  } else {
    ref.invalidate(seriesDetailProvider);
  }
  ref.invalidate(seriesBooksProvider);
  ref.invalidate(ondeckProvider);
  ref.invalidate(recentSeriesProvider);
  ref.invalidate(libraryShelfProvider);
  ref.invalidate(pinnedSeriesProvider);
  ref.read(readStatusEpochProvider.notifier).bump();
}

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
