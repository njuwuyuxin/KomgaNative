import 'dart:async';

import 'package:drift/drift.dart';
import 'package:komga_native/src/data/cache/http_cache_tables.dart';

export 'package:komga_native/src/data/cache/http_cache_tables.dart';

part 'http_cache_database.g.dart';
part 'http_cache_downloads_dao.dart';

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

  Stream<Set<TableUpdate>> cachedResponsesUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(cachedResponses));

  Stream<Set<TableUpdate>> downloadedBooksUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(downloadedBooks));

  Future<void> clear({String? scope}) async {
    final statement = delete(cachedResponses)
      ..where(
        (t) => scope == null
            ? t.pinned.equals(false)
            : t.pinned.equals(false) & t.scope.equals(scope),
      );
    await statement.go();
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
