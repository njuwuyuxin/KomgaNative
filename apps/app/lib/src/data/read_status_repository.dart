import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 阅读状态变更限界上下文仓库（整系列/单本书标记已读与未读，UI-P2-5 / ARC-09）。
abstract interface class ReadStatusRepository {
  /// 把整个系列标记已读/未读：服务端请求 + 本地进度同步对齐。
  Future<void> setSeriesRead(String seriesId, {required bool read});

  /// 把单本书标记已读/未读。
  Future<void> setBookRead(
    String bookId, {
    required bool read,
    required int pagesCount,
  });
}

class KomgaReadStatusRepository implements ReadStatusRepository {
  const KomgaReadStatusRepository(this._session, this._sync);

  final KomgaSession _session;
  final ProgressSyncService _sync;

  KomgaSession get debugSession => _session;

  @override
  Future<void> setSeriesRead(String seriesId, {required bool read}) async {
    try {
      final books = await _session.fetchSeriesBooks(seriesId, size: 100);
      if (read) {
        await _session.markSeriesRead(seriesId);
      } else {
        await _session.markSeriesUnread(seriesId);
      }
      final now = DateTime.now().toUtc();
      for (final book in books.items) {
        await _sync.forceAdopt(
          book.id,
          read
              ? ReadProgress(
                  page: book.pagesCount,
                  completed: true,
                  lastModified: now,
                )
              : null,
        );
      }
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<void> setBookRead(
    String bookId, {
    required bool read,
    required int pagesCount,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      if (read) {
        await _session.updateReadProgress(
          bookId,
          page: pagesCount <= 0 ? null : pagesCount,
          completed: true,
        );
        await _sync.forceAdopt(
          bookId,
          ReadProgress(
            page: pagesCount <= 0 ? 1 : pagesCount,
            completed: true,
            lastModified: now,
          ),
        );
      } else {
        await _session.markBookUnread(bookId);
        await _sync.forceAdopt(bookId, null);
      }
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }
}
