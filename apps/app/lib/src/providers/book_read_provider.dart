import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/library_providers.dart';

/// 单本书的阅读状态写入（标记已读 / 未读，UI-P2-5）。
///
/// 与 `seriesReadProvider` 同一套做法：状态里放"正在处理哪些书"，
/// 用来禁用菜单 / 避免连点；写完让详情、书列表、继续阅读都重新取。
class BookReadController extends Notifier<Set<String>> {
  bool _disposed = false;

  @override
  Set<String> build() {
    ref.onDispose(() => _disposed = true);
    return const <String>{};
  }

  Future<void> setRead(
    String bookId, {
    required bool read,
    required int pagesCount,
  }) async {
    if (state.contains(bookId)) return;
    state = <String>{...state, bookId};
    try {
      await ref
          .read(readStatusRepositoryProvider)
          .setBookRead(bookId, read: read, pagesCount: pagesCount);
      if (_disposed) return;
      ref.invalidate(ondeckProvider);
    } finally {
      if (!_disposed) state = <String>{...state}..remove(bookId);
    }
  }

  bool isBusy(String bookId) => state.contains(bookId);
}

final bookReadProvider = NotifierProvider<BookReadController, Set<String>>(
  BookReadController.new,
);
