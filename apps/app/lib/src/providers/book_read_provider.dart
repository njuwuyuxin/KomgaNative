import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';

/// 单本书的阅读状态写入（标记已读 / 未读，UI-P2-5 / ARC-10）。
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
    String? seriesId,
    String? sourceKey,
  }) async {
    if (state.contains(bookId)) return;
    state = <String>{...state, bookId};
    try {
      await ref
          .read(readStatusRepositoryForSourceProvider(sourceKey))
          .setBookRead(bookId, read: read, pagesCount: pagesCount);
      if (_disposed) return;
      invalidateAfterReadStatusChange(
        ref,
        seriesId: seriesId,
        sourceKey: sourceKey,
      );
    } finally {
      if (!_disposed) state = <String>{...state}..remove(bookId);
    }
  }

  bool isBusy(String bookId) => state.contains(bookId);
}

final bookReadProvider = NotifierProvider<BookReadController, Set<String>>(
  BookReadController.new,
);
