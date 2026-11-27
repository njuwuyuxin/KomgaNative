part of 'progress_database.dart';

/// [ProgressDatabase] 的置顶系列、阅读会话历史与旧库平滑迁移扩展（ARC-12）。
extension ProgressUserDao on ProgressDatabase {
  Future<void> _upgradeLocalProgressToV3(String escapedScope) async {
    await customStatement('''
      CREATE TABLE local_progress_v3 (
        scope TEXT NOT NULL DEFAULT '',
        book_id TEXT NOT NULL,
        page INTEGER NOT NULL,
        completed INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        server_last_modified INTEGER NULL,
        pending_seq INTEGER NULL,
        PRIMARY KEY (scope, book_id)
      )
    ''');
    await customStatement(
      'INSERT OR REPLACE INTO local_progress_v3 '
      '(scope, book_id, page, completed, updated_at, server_last_modified, pending_seq) '
      "SELECT '$escapedScope', book_id, page, completed, updated_at, server_last_modified, pending_seq "
      'FROM local_progress',
    );
    await customStatement('DROP TABLE local_progress');
    await customStatement(
      'ALTER TABLE local_progress_v3 RENAME TO local_progress',
    );
  }

  Future<void> _backfillEmptyScopesToV7() async {
    const escapedLocal = kLocalSourceKey;
    // 1) local_progress（复合主键 (scope, book_id)）
    await customStatement(
      'INSERT OR IGNORE INTO local_progress '
      '(scope, book_id, page, completed, updated_at, server_last_modified, pending_seq) '
      "SELECT '$escapedLocal', book_id, page, completed, updated_at, server_last_modified, pending_seq "
      "FROM local_progress WHERE scope = ''",
    );
    await customStatement("DELETE FROM local_progress WHERE scope = ''");

    // 2) reading_sessions（自增主键 id）
    await customStatement(
      "UPDATE reading_sessions SET scope = '$escapedLocal' WHERE scope = ''",
    );

    // 3) pinned_series_rows（复合主键 (server_id, series_id)）
    await customStatement(
      'INSERT OR IGNORE INTO pinned_series_rows (server_id, series_id, created_at) '
      "SELECT '$escapedLocal', series_id, created_at "
      "FROM pinned_series_rows WHERE server_id = ''",
    );
    await customStatement(
      "DELETE FROM pinned_series_rows WHERE server_id = ''",
    );

    // 4) page_bookmarks_rows（复合主键 (scope, book_id, page)）
    await customStatement(
      'INSERT OR IGNORE INTO page_bookmarks_rows '
      '(scope, book_id, page, note, created_at) '
      "SELECT '$escapedLocal', book_id, page, note, created_at "
      "FROM page_bookmarks_rows WHERE scope = ''",
    );
    await customStatement("DELETE FROM page_bookmarks_rows WHERE scope = ''");
  }

  Future<void> _migrateFromLegacyCacheIfNeeded() async {
    final resolver = legacyCacheDbPath;
    if (resolver == null) return;
    try {
      final path = await resolver();
      if (path == null || path.isEmpty || !File(path).existsSync()) return;
      final escapedPath = path.replaceAll("'", "''");
      final rawScope = await defaultLegacyScope?.call() ?? '';
      final effectiveScope = rawScope.isEmpty ? kLocalSourceKey : rawScope;
      final escapedScope = effectiveScope.replaceAll("'", "''");
      await customStatement("ATTACH DATABASE '$escapedPath' AS legacy_cache");
      try {
        final tablesRows = await customSelect(
          'SELECT name FROM legacy_cache.sqlite_master '
          "WHERE type = 'table' AND name IN ('pinned_series_rows', 'reading_sessions')",
        ).get();
        final legacyTables = <String>{
          for (final row in tablesRows) row.read<String>('name'),
        };
        if (legacyTables.contains('pinned_series_rows')) {
          await customStatement(
            'INSERT OR IGNORE INTO pinned_series_rows (server_id, series_id, created_at) '
            'SELECT server_id, series_id, created_at FROM legacy_cache.pinned_series_rows',
          );
          await _tryDropLegacy('pinned_series_rows');
        }
        if (legacyTables.contains('reading_sessions')) {
          await customStatement(
            'INSERT OR IGNORE INTO reading_sessions '
            '(id, scope, book_id, series_id, book_name, started_at, ended_at, duration_ms, start_page, end_page, completed) '
            "SELECT id, '$escapedScope', book_id, series_id, book_name, started_at, ended_at, duration_ms, start_page, end_page, completed "
            'FROM legacy_cache.reading_sessions',
          );
          await _tryDropLegacy('reading_sessions');
        }
      } finally {
        await customStatement('DETACH DATABASE legacy_cache');
      }
    } on Object catch (error) {
      // 迁移失败绝不阻塞用户库打开。
      debugPrint('ProgressUserDao: legacy v5 migration skipped: $error');
    }
  }

  Future<void> _tryDropLegacy(String table) async {
    try {
      await customStatement('DROP TABLE IF EXISTS legacy_cache.$table');
    } on Object catch (error) {
      // 缓存库被写锁占用时下次仍可幂等重试。
      debugPrint('ProgressUserDao: drop legacy table $table skipped: $error');
    }
  }

  Future<List<String>> pinnedSeries(String serverId) async {
    final rows =
        await (select(pinnedSeriesRows)
              ..where((PinnedSeriesRows t) => t.serverId.equals(serverId))
              ..orderBy(<OrderClauseGenerator<PinnedSeriesRows>>[
                (PinnedSeriesRows t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (PinnedSeriesRows t) => OrderingTerm(expression: t.seriesId),
              ]))
            .get();
    return <String>[for (final row in rows) row.seriesId];
  }

  Stream<Set<TableUpdate>> pinnedSeriesUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(pinnedSeriesRows));

  Future<void> setPinned({
    required String serverId,
    required String seriesId,
    required bool pinned,
  }) async {
    if (!pinned) {
      await (delete(pinnedSeriesRows)..where(
            (PinnedSeriesRows t) =>
                t.serverId.equals(serverId) & t.seriesId.equals(seriesId),
          ))
          .go();
      return;
    }
    await into(pinnedSeriesRows).insertOnConflictUpdate(
      PinnedSeriesRowsCompanion.insert(
        serverId: serverId,
        seriesId: seriesId,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> replacePinnedSeries(
    String serverId,
    List<String> seriesIds,
  ) async {
    await transaction(() async {
      await (delete(
        pinnedSeriesRows,
      )..where((PinnedSeriesRows t) => t.serverId.equals(serverId))).go();
      final base = DateTime.now().toUtc();
      final unique = seriesIds.toSet().toList(growable: false);
      for (var i = 0; i < unique.length; i++) {
        await into(pinnedSeriesRows).insertOnConflictUpdate(
          PinnedSeriesRowsCompanion.insert(
            serverId: serverId,
            seriesId: unique[i],
            createdAt: base.subtract(Duration(seconds: i)),
          ),
        );
      }
    });
  }

  Future<int> addReadingSession({
    String scope = kLocalSourceKey,
    required String bookId,
    required String seriesId,
    required String bookName,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationMs,
    required int startPage,
    required int endPage,
    required bool completed,
  }) {
    final normalizedScope = scope.isEmpty ? kLocalSourceKey : scope;
    return into(readingSessions).insert(
      ReadingSessionsCompanion.insert(
        scope: Value<String>(normalizedScope),
        bookId: bookId,
        seriesId: seriesId,
        bookName: Value<String>(bookName),
        startedAt: startedAt,
        endedAt: endedAt,
        durationMs: durationMs,
        startPage: Value<int>(startPage),
        endPage: Value<int>(endPage),
        completed: Value<bool>(completed),
      ),
    );
  }

  Future<List<ReadingSession>> readingSessionList({
    String? scope,
    Set<String>? scopes,
    int limit = 200,
  }) {
    final query = select(readingSessions);
    if (scopes != null && scopes.isNotEmpty) {
      query.where((ReadingSessions t) => t.scope.isIn(scopes));
    } else if (scope != null && scope.isNotEmpty) {
      query.where((ReadingSessions t) => t.scope.equals(scope));
    }
    query
      ..orderBy(<OrderClauseGenerator<ReadingSessions>>[
        (ReadingSessions t) =>
            OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.get();
  }

  Stream<Set<TableUpdate>> readingSessionsUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(readingSessions));

  Future<void> deleteReadingSession(int id) => (delete(
    readingSessions,
  )..where((ReadingSessions t) => t.id.equals(id))).go();

  Future<void> deleteReadingSessions(Iterable<int> ids) {
    final list = ids.toSet().toList(growable: false);
    if (list.isEmpty) return Future<void>.value();
    return (delete(
      readingSessions,
    )..where((ReadingSessions t) => t.id.isIn(list))).go();
  }

  Future<void> clearReadingSessions({String? scope, Set<String>? scopes}) {
    final stmt = delete(readingSessions);
    if (scopes != null && scopes.isNotEmpty) {
      stmt.where((ReadingSessions t) => t.scope.isIn(scopes));
    } else if (scope != null && scope.isNotEmpty) {
      stmt.where((ReadingSessions t) => t.scope.equals(scope));
    }
    return stmt.go();
  }
}
