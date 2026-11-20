part of 'http_cache_database.dart';

/// [HttpCacheDatabase] 的整本下载记录、下载队列与迁移扩展（ARC-12）。
extension HttpCacheDownloadsDao on HttpCacheDatabase {
  Future<void> _upgradeDownloadedBooksToV6(String escapedScope) async {
    await customStatement('''
      CREATE TABLE downloaded_books_v6 (
        scope TEXT NOT NULL DEFAULT '',
        book_id TEXT NOT NULL,
        series_id TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        bytes INTEGER NOT NULL,
        saved_at INTEGER NOT NULL,
        PRIMARY KEY (scope, book_id)
      )
    ''');
    await customStatement(
      'INSERT OR REPLACE INTO downloaded_books_v6 '
      '(scope, book_id, series_id, page_count, bytes, saved_at) '
      "SELECT '$escapedScope', book_id, series_id, page_count, bytes, saved_at "
      'FROM downloaded_books',
    );
    await customStatement('DROP TABLE downloaded_books');
    await customStatement(
      'ALTER TABLE downloaded_books_v6 RENAME TO downloaded_books',
    );
  }

  Future<void> _upgradeDownloadQueueToV6(String escapedScope) async {
    await customStatement('''
      CREATE TABLE download_queue_entries_v6 (
        scope TEXT NOT NULL DEFAULT '',
        book_id TEXT NOT NULL,
        series_id TEXT NOT NULL,
        name TEXT NOT NULL,
        number TEXT NOT NULL DEFAULT '',
        pages_count INTEGER NOT NULL,
        state TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (scope, book_id)
      )
    ''');
    await customStatement(
      'INSERT OR REPLACE INTO download_queue_entries_v6 '
      '(scope, book_id, series_id, name, number, pages_count, state, done, total, created_at) '
      "SELECT '$escapedScope', book_id, series_id, name, number, pages_count, state, done, total, created_at "
      'FROM download_queue_entries',
    );
    await customStatement('DROP TABLE download_queue_entries');
    await customStatement(
      'ALTER TABLE download_queue_entries_v6 RENAME TO download_queue_entries',
    );
  }

  Future<int> setBookPagesPinned({
    required String scope,
    required String bookId,
    required bool pinned,
  }) {
    final fragment = '/books/$bookId/pages/';
    return (update(cachedResponses)
          ..where((t) => t.scope.equals(scope) & t.url.contains(fragment)))
        .write(CachedResponsesCompanion(pinned: Value<bool>(pinned)));
  }

  Future<void> markDownloaded({
    String scope = '',
    required String bookId,
    required String seriesId,
    required int pageCount,
    required int bytes,
  }) async {
    await setBookPagesPinned(scope: scope, bookId: bookId, pinned: true);
    await into(downloadedBooks).insertOnConflictUpdate(
      DownloadedBooksCompanion.insert(
        scope: Value<String>(scope),
        bookId: bookId,
        seriesId: seriesId,
        pageCount: pageCount,
        bytes: bytes,
        savedAt: _now(),
      ),
    );
  }

  Future<DownloadedBook?> download(String bookId, {String scope = ''}) {
    return (select(downloadedBooks)
          ..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId)))
        .getSingleOrNull();
  }

  Future<List<DownloadedBook>> downloads({String? scope}) {
    final query = select(downloadedBooks);
    if (scope != null) query.where((t) => t.scope.equals(scope));
    return query.get();
  }

  Future<CacheUsage> downloadsUsage({String? scope}) async {
    final byteSum = downloadedBooks.bytes.sum();
    final count = downloadedBooks.bookId.count();
    final query = selectOnly(downloadedBooks)
      ..addColumns(<Expression<Object>>[byteSum, count]);
    if (scope != null) query.where(downloadedBooks.scope.equals(scope));
    final row = await query.getSingle();
    return CacheUsage(
      bytes: row.read(byteSum) ?? 0,
      entries: row.read(count) ?? 0,
    );
  }

  Future<void> removeDownload(String bookId, {String scope = ''}) async {
    await (delete(
      downloadedBooks,
    )..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))).go();
  }

  Future<void> enqueueDownload({
    String scope = '',
    required String bookId,
    required String seriesId,
    required String name,
    required String number,
    required int pagesCount,
  }) async {
    await into(downloadQueueEntries).insertOnConflictUpdate(
      DownloadQueueEntriesCompanion.insert(
        scope: Value<String>(scope),
        bookId: bookId,
        seriesId: seriesId,
        name: name,
        number: Value<String>(number),
        pagesCount: pagesCount,
        state: 'queued',
        createdAt: _now(),
      ),
    );
  }

  Future<void> updateQueueEntry({
    String scope = '',
    required String bookId,
    required String state,
    required int done,
    required int total,
  }) async {
    await (update(
      downloadQueueEntries,
    )..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))).write(
      DownloadQueueEntriesCompanion(
        state: Value<String>(state),
        done: Value<int>(done),
        total: Value<int>(total),
      ),
    );
  }

  Future<void> dequeueDownload(String bookId, {String scope = ''}) async {
    await (delete(
      downloadQueueEntries,
    )..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))).go();
  }

  Future<void> clearDownloadQueue({String? scope}) {
    final stmt = delete(downloadQueueEntries);
    if (scope != null) stmt.where((t) => t.scope.equals(scope));
    return stmt.go();
  }

  Future<List<DownloadQueueEntry>> downloadQueue({String? scope}) {
    final query = select(downloadQueueEntries);
    if (scope != null) query.where((t) => t.scope.equals(scope));
    query.orderBy(<OrderClauseGenerator<DownloadQueueEntries>>[
      (t) => OrderingTerm(expression: t.createdAt),
      (t) => OrderingTerm(expression: t.bookId),
    ]);
    return query.get();
  }

  Future<int> deleteCachedPages({
    required String scope,
    required String bookId,
  }) {
    final fragment = '/books/$bookId/pages/';
    return (delete(
      cachedResponses,
    )..where((t) => t.scope.equals(scope) & t.url.contains(fragment))).go();
  }
}
