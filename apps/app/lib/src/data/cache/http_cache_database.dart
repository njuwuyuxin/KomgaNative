import 'dart:async';

import 'package:drift/drift.dart';
import 'package:komga_native/src/data/cache/http_cache_tables.dart';

export 'package:komga_native/src/data/cache/http_cache_tables.dart';

part 'http_cache_database.g.dart';

@DriftDatabase(
  tables: <Type>[CachedResponses, DownloadedBooks, DownloadQueueEntries],
)
class HttpCacheDatabase extends _$HttpCacheDatabase {
  HttpCacheDatabase(
    super.executor, {
    this.maxImageBytes = defaultMaxImageBytes,
    this.maxJsonRows = 400,
    this.defaultLegacyScope,
  });

  static const int defaultMaxImageBytes = 256 * 1024 * 1024;

  final int maxImageBytes;
  final int maxJsonRows;

  /// 旧单服下载表升级到 v6 复合主键时用于回填的活动服务器 `baseUrl`。
  final FutureOr<String> Function()? defaultLegacyScope;

  int? _seqSeed;

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) await m.createTable(downloadedBooks);
      if (from < 3) await m.createTable(downloadQueueEntries);
      if (from < 6) {
        final rawScope = await defaultLegacyScope?.call() ?? '';
        final escaped = rawScope.replaceAll("'", "''");
        if (from >= 2) await _upgradeDownloadedBooksToV6(escaped);
        if (from >= 3) await _upgradeDownloadQueueToV6(escaped);
      }
      if (from < 7) {
        await m.addColumn(cachedResponses, cachedResponses.pinned);
        await customStatement('''
          UPDATE cached_responses
          SET pinned = 1
          WHERE EXISTS (
            SELECT 1 FROM downloaded_books d
            WHERE d.scope = cached_responses.scope
              AND cached_responses.url LIKE '%/books/' || d.book_id || '/pages/%'
          )
        ''');
      }
    },
  );

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

  Future<CachedResponse?> read(String scope, String url) async {
    final row =
        await (select(cachedResponses)
              ..where((t) => t.scope.equals(scope) & t.url.equals(url)))
            .getSingleOrNull();
    if (row == null) return null;
    await (update(
      cachedResponses,
    )..where((t) => t.scope.equals(scope) & t.url.equals(url))).write(
      CachedResponsesCompanion(lastUsedSeq: Value<int>(await _nextSeq())),
    );
    return row;
  }

  Future<void> write(
    String scope,
    String url,
    String kind,
    Uint8List body, {
    bool pinned = false,
  }) async {
    final seq = await _nextSeq();
    await into(cachedResponses).insert(
      CachedResponsesCompanion.insert(
        scope: scope,
        url: url,
        kind: kind,
        byteSize: body.length,
        body: body,
        lastUsedSeq: seq,
        pinned: Value<bool>(pinned),
      ),
      onConflict: DoUpdate(
        (CachedResponses old) => CachedResponsesCompanion(
          kind: Value<String>(kind),
          byteSize: Value<int>(body.length),
          body: Value<Uint8List>(body),
          lastUsedSeq: Value<int>(seq),
          // 若该页本就已作为整本下载被钉住（pinned=true），在线重读不得把它降级为被动缓存。
          pinned: pinned ? const Value<bool>(true) : const Value<bool>.absent(),
        ),
      ),
    );
    if (kind == 'image') {
      if (!pinned) await _evictImages(keepUrl: url);
    } else {
      await _pruneJson(scope);
    }
  }

  /// 被动浏览缓存占用（不含 `pinned = true` 的已整本下载页图，ARC-08）。
  Future<CacheUsage> usage({String? scope}) async {
    final byteSum = cachedResponses.byteSize.sum();
    final count = cachedResponses.url.count();
    final query = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[byteSum, count]);
    final unpinned = cachedResponses.pinned.equals(false);
    query.where(
      scope == null ? unpinned : unpinned & cachedResponses.scope.equals(scope),
    );
    final row = await query.getSingle();
    return CacheUsage(
      bytes: row.read(byteSum) ?? 0,
      entries: row.read(count) ?? 0,
    );
  }

  /// 清空被动浏览缓存（保留 `pinned = true` 的已下载书籍及其页图，ARC-08）。
  Future<void> clear({String? scope}) async {
    final statement = delete(cachedResponses)
      ..where(
        (t) => scope == null
            ? t.pinned.equals(false)
            : t.pinned.equals(false) & t.scope.equals(scope),
      );
    await statement.go();
  }

  /// 将某本书已缓存的页图标记/取消标记为受保护（ARC-08）。
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

  // ---- 整本下载记录（按 scope 分区）----

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

  // ---- 下载队列（按 scope 分区）----

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

  Future<void> _evictImages({required String keepUrl}) async {
    var over = await _imageBytes() - maxImageBytes;
    while (over > 0) {
      final rows = await _oldestImages();
      if (rows.isEmpty) return;
      var removedAny = false;
      for (final row in rows) {
        if (over <= 0) return;
        if (row.url == keepUrl) continue;
        await _deleteRow(row);
        over -= row.byteSize;
        removedAny = true;
      }
      if (!removedAny) return;
    }
  }

  Future<List<CachedResponse>> _oldestImages() {
    return (select(cachedResponses)
          ..where((t) => t.kind.equals('image') & t.pinned.equals(false))
          ..orderBy(<OrderClauseGenerator<CachedResponses>>[
            (t) => OrderingTerm(expression: t.lastUsedSeq),
          ])
          ..limit(32))
        .get();
  }

  Future<int> _imageBytes() async {
    final byteSum = cachedResponses.byteSize.sum();
    final query = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[byteSum])
      ..where(
        cachedResponses.kind.equals('image') &
            cachedResponses.pinned.equals(false),
      );
    final row = await query.getSingle();
    return row.read(byteSum) ?? 0;
  }

  Future<void> _pruneJson(String scope) async {
    final count = cachedResponses.url.count();
    final counting = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        cachedResponses.scope.equals(scope) &
            cachedResponses.kind.equals('json'),
      );
    var over = ((await counting.getSingle()).read(count) ?? 0) - maxJsonRows;
    while (over > 0) {
      final rows =
          await (select(cachedResponses)
                ..where((t) => t.scope.equals(scope) & t.kind.equals('json'))
                ..orderBy(<OrderClauseGenerator<CachedResponses>>[
                  (t) => OrderingTerm(expression: t.lastUsedSeq),
                ])
                ..limit(32))
              .get();
      if (rows.isEmpty) return;
      for (final row in rows) {
        if (over <= 0) return;
        await _deleteRow(row);
        over--;
      }
    }
  }

  Future<void> _deleteRow(CachedResponse row) {
    return (delete(
      cachedResponses,
    )..where((t) => t.scope.equals(row.scope) & t.url.equals(row.url))).go();
  }

  Future<int> _nextSeq() async {
    final seed = _seqSeed ?? await _maxSeq();
    final now = DateTime.now().microsecondsSinceEpoch;
    final seq = now > seed ? now : seed + 1;
    _seqSeed = seq;
    return seq;
  }

  Future<int> _maxSeq() async {
    final maxSeq = cachedResponses.lastUsedSeq.max();
    final query = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[maxSeq]);
    final row = await query.getSingle();
    return row.read(maxSeq) ?? 0;
  }

  DateTime _now() => DateTime.now().toUtc();
}
