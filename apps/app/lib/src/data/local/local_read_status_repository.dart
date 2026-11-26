import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 本机书库的已读/未读状态仓库：直接读写 `kLocalSourceKey` 分区，零网络请求。
final class LocalReadStatusRepository implements ReadStatusRepository {
  const LocalReadStatusRepository(this._db, this._sync);

  final ProgressDatabase _db;
  final ProgressSyncService _sync;

  @override
  Future<void> setSeriesRead(String seriesId, {required bool read}) async {
    final booksPage = await _db.queryLocalSeriesBooks(seriesId, size: 10000);
    final now = DateTime.now().toUtc();
    for (final book in booksPage.items) {
      await _sync.forceAdopt(
        book.id,
        read
            ? ReadProgress(
                page: book.pagesCount <= 0 ? 1 : book.pagesCount,
                completed: true,
                lastModified: now,
              )
            : null,
        scope: kLocalSourceKey,
      );
    }
  }

  @override
  Future<void> setBookRead(
    String bookId, {
    required bool read,
    required int pagesCount,
  }) async {
    final now = DateTime.now().toUtc();
    await _sync.forceAdopt(
      bookId,
      read
          ? ReadProgress(
              page: pagesCount <= 0 ? 1 : pagesCount,
              completed: true,
              lastModified: now,
            )
          : null,
      scope: kLocalSourceKey,
    );
  }
}
