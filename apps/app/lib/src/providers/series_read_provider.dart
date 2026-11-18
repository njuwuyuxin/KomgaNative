import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/library_providers.dart';

/// 系列级阅读状态写入（标记全部已读 / 未读）。
///
/// 状态里放"正在处理哪些系列"，用于禁用菜单/显示进度——避免用户连点两次，
/// 也避免在请求途中把界面切走又回来看到旧状态。
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
          .read(libraryRepositoryProvider)
          .setSeriesRead(seriesId, read: read);
      if (_disposed) return;
      // 服务端已经改了：让详情、书列表、继续阅读都重新取。
      ref.invalidate(seriesDetailProvider(seriesId));
      // 书列表是 family（每本书数一档），invalidate 整个 family 最省事也最稳。
      ref.invalidate(seriesBooksProvider);
      ref.invalidate(ondeckProvider);
    } finally {
      if (!_disposed) state = <String>{...state}..remove(seriesId);
    }
  }
}

final seriesReadProvider = NotifierProvider<SeriesReadController, Set<String>>(
  SeriesReadController.new,
);
