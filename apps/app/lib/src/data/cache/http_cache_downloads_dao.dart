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

  Future<void> _backfillEmptyScopesToV9(String targetScope) async {
    final escaped = targetScope.replaceAll("'", "''");
    // 1) downloaded_books：若同一 book_id 在 '' 与目标 scope 下并存，按 saved_at 保留更新的那条。
    await customStatement('''
      UPDATE downloaded_books
      SET
        series_id = (SELECT e.series_id FROM downloaded_books e WHERE e.scope = '' AND e.book_id = downloaded_books.book_id),
        book_name = (SELECT e.book_name FROM downloaded_books e WHERE e.scope = '' AND e.book_id = downloaded_books.book_id),
        page_count = (SELECT e.page_count FROM downloaded_books e WHERE e.scope = '' AND e.book_id = downloaded_books.book_id),
        bytes = (SELECT e.bytes FROM downloaded_books e WHERE e.scope = '' AND e.book_id = downloaded_books.book_id),
        saved_at = (SELECT e.saved_at FROM downloaded_books e WHERE e.scope = '' AND e.book_id = downloaded_books.book_id)
      WHERE scope = '$escaped'
        AND EXISTS (
          SELECT 1 FROM downloaded_books e
          WHERE e.scope = ''
            AND e.book_id = downloaded_books.book_id
            AND e.saved_at > downloaded_books.saved_at
        )
    ''');
    await customStatement(
      'INSERT OR IGNORE INTO downloaded_books '
      '(scope, book_id, series_id, book_name, page_count, bytes, saved_at) '
      "SELECT '$escaped', book_id, series_id, book_name, page_count, bytes, saved_at "
      "FROM downloaded_books WHERE scope = ''",
    );
    await customStatement("DELETE FROM downloaded_books WHERE scope = ''");

    // 2) download_queue_entries：冲突时按 created_at 保留更新的排队记录。
    await customStatement('''
      UPDATE download_queue_entries
      SET
        series_id = (SELECT e.series_id FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        name = (SELECT e.name FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        number = (SELECT e.number FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        pages_count = (SELECT e.pages_count FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        state = (SELECT e.state FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        done = (SELECT e.done FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        total = (SELECT e.total FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id),
        created_at = (SELECT e.created_at FROM download_queue_entries e WHERE e.scope = '' AND e.book_id = download_queue_entries.book_id)
      WHERE scope = '$escaped'
        AND EXISTS (
          SELECT 1 FROM download_queue_entries e
          WHERE e.scope = ''
            AND e.book_id = download_queue_entries.book_id
            AND e.created_at > download_queue_entries.created_at
        )
    ''');
    await customStatement(
      'INSERT OR IGNORE INTO download_queue_entries '
      '(scope, book_id, series_id, name, number, pages_count, state, done, total, created_at) '
      "SELECT '$escaped', book_id, series_id, name, number, pages_count, state, done, total, created_at "
      "FROM download_queue_entries WHERE scope = ''",
    );
    await customStatement(
      "DELETE FROM download_queue_entries WHERE scope = ''",
    );

    // 3) cached_responses：同步清理遗留的空 scope 缓存行。
    await customStatement(
      'INSERT OR IGNORE INTO cached_responses '
      '(scope, url, kind, byte_size, body, last_used_seq, pinned) '
      "SELECT '$escaped', url, kind, byte_size, body, last_used_seq, pinned "
      "FROM cached_responses WHERE scope = ''",
    );
    await customStatement("DELETE FROM cached_responses WHERE scope = ''");
  }

  Future<int> setBookPagesPinned({
    required String scope,
    required String bookId,
    required bool pinned,
  }) {
    final pageFragment = '/books/$bookId/pages/';
    return (update(cachedResponses)..where(
          (t) =>
              t.scope.equals(scope) &
              (t.url.contains(pageFragment) |
                  t.url.like('%/books/$bookId/pages') |
                  t.url.like('%/books/$bookId')),
        ))
        .write(CachedResponsesCompanion(pinned: Value<bool>(pinned)));
  }

  Future<void> markDownloaded({
    required String scope,
    required String bookId,
    required String seriesId,
    String bookName = '',
    required int pageCount,
    required int bytes,
  }) async {
    assert(scope.isNotEmpty, 'markDownloaded requires a non-empty scope');
    await setBookPagesPinned(scope: scope, bookId: bookId, pinned: true);
    await into(downloadedBooks).insertOnConflictUpdate(
      DownloadedBooksCompanion.insert(
        scope: scope,
        bookId: bookId,
        seriesId: seriesId,
        bookName: Value<String>(bookName),
        pageCount: pageCount,
        bytes: bytes,
        savedAt: _now(),
      ),
    );
  }

  Future<DownloadedBook?> download(String bookId, {required String scope}) {
    assert(scope.isNotEmpty, 'download requires a non-empty scope');
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

  Future<void> removeDownload(String bookId, {required String scope}) async {
    assert(scope.isNotEmpty, 'removeDownload requires a non-empty scope');
    await (delete(
      downloadedBooks,
    )..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))).go();
  }

  Future<void> enqueueDownload({
    required String scope,
    required String bookId,
    required String seriesId,
    required String name,
    required String number,
    required int pagesCount,
  }) async {
    assert(scope.isNotEmpty, 'enqueueDownload requires a non-empty scope');
    await into(downloadQueueEntries).insertOnConflictUpdate(
      DownloadQueueEntriesCompanion.insert(
        scope: scope,
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
    required String scope,
    required String bookId,
    required String state,
    required int done,
    required int total,
  }) async {
    assert(scope.isNotEmpty, 'updateQueueEntry requires a non-empty scope');
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

  Future<void> dequeueDownload(String bookId, {required String scope}) async {
    assert(scope.isNotEmpty, 'dequeueDownload requires a non-empty scope');
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
  }) async {
    // 解除元数据 JSON（book / pages）的保护标记，让它们回归普通被动缓存策略。
    await setBookPagesPinned(scope: scope, bookId: bookId, pinned: false);
    final fragment = '/books/$bookId/pages/';
    return (delete(
      cachedResponses,
    )..where((t) => t.scope.equals(scope) & t.url.contains(fragment))).go();
  }
}
