import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/user_tables.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

export 'package:komga_native/src/data/progress/user_tables.dart';

part 'progress_database.g.dart';

/// 用户本地资产数据库（`komga_native.sqlite`）：阅读进度、系列置顶与阅读会话统计。
///
/// 与随时可清空重建的 `komga_cache.sqlite` 严格物理隔离（ARC-06）。
@DriftDatabase(tables: <Type>[LocalProgress, PinnedSeriesRows, ReadingSessions])
class ProgressDatabase extends _$ProgressDatabase {
  ProgressDatabase(super.executor, {this.legacyCacheDbPath});

  /// 旧版 v5 `komga_cache.sqlite` 的文件路径提供器（首次升级平滑迁入置顶与阅读历史）。
  final FutureOr<String?> Function()? legacyCacheDbPath;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(pinnedSeriesRows);
        await m.createTable(readingSessions);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await _migrateFromLegacyCacheIfNeeded();
    },
  );

  /// 一次性平滑迁入旧缓存库里的 `pinned_series_rows` 与 `reading_sessions`。
  Future<void> _migrateFromLegacyCacheIfNeeded() async {
    final resolver = legacyCacheDbPath;
    if (resolver == null) return;
    try {
      final path = await resolver();
      if (path == null || path.isEmpty || !File(path).existsSync()) return;
      final escaped = path.replaceAll("'", "''");
      await customStatement("ATTACH DATABASE '$escaped' AS legacy_cache");
      try {
        final tablesRows = await customSelect(
          "SELECT name FROM legacy_cache.sqlite_master "
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
            '(id, book_id, series_id, book_name, started_at, ended_at, duration_ms, start_page, end_page, completed) '
            'SELECT id, book_id, series_id, book_name, started_at, ended_at, duration_ms, start_page, end_page, completed '
            'FROM legacy_cache.reading_sessions',
          );
          await _tryDropLegacy('reading_sessions');
        }
      } finally {
        await customStatement('DETACH DATABASE legacy_cache');
      }
    } on Object {
      // 迁移失败（旧库损坏/锁竞争）绝不阻塞用户库打开。
    }
  }

  Future<void> _tryDropLegacy(String table) async {
    try {
      await customStatement('DROP TABLE IF EXISTS legacy_cache.$table');
    } on Object {
      // 若缓存库正被后台连接写锁占用，下次打开仍可幂等重试。
    }
  }

  int _seqSeed = 0;

  // ---- 阅读进度 ----

  Future<int> enqueue(ProgressTarget target) async {
    final now = DateTime.now().toUtc();
    final micros = now.microsecondsSinceEpoch;
    final seq = micros > _seqSeed ? micros : _seqSeed + 1;
    _seqSeed = seq;
    await into(localProgress).insertOnConflictUpdate(
      LocalProgressCompanion.insert(
        bookId: target.bookId,
        page: target.page,
        completed: target.completed,
        updatedAt: now,
        pendingSeq: Value<int>(seq),
      ),
    );
    return seq;
  }

  Future<bool> ack(String bookId, int seq) async {
    final updated =
        await (update(localProgress)..where(
              (LocalProgress t) =>
                  t.bookId.equals(bookId) & t.pendingSeq.equals(seq),
            ))
            .write(
              const LocalProgressCompanion(
                pendingSeq: Value<int?>(null),
                serverLastModified: Value<DateTime?>(null),
              ),
            );
    return updated > 0;
  }

  Future<LocalProgressData?> record(String bookId) => (select(
    localProgress,
  )..where((t) => t.bookId.equals(bookId))).getSingleOrNull();

  Future<List<LocalProgressData>> records(List<String> bookIds) async {
    if (bookIds.isEmpty) return const <LocalProgressData>[];
    return (select(localProgress)..where((t) => t.bookId.isIn(bookIds))).get();
  }

  Future<List<PendingProgress>> pending() async {
    final rows =
        await (select(localProgress)
              ..where((t) => t.pendingSeq.isNotNull())
              ..orderBy(<OrderClauseGenerator<LocalProgress>>[
                (t) => OrderingTerm(expression: t.pendingSeq),
              ]))
            .get();
    return <PendingProgress>[
      for (final row in rows)
        PendingProgress(
          ProgressTarget(
            bookId: row.bookId,
            page: row.page,
            completed: row.completed,
          ),
          row.pendingSeq!,
        ),
    ];
  }

  Future<void> adoptRemote(String bookId, ReadProgress? remote) async {
    final current = await record(bookId);
    if (current?.pendingSeq != null) return;

    if (remote == null) {
      await (delete(localProgress)..where((t) => t.bookId.equals(bookId))).go();
      return;
    }
    await into(localProgress).insertOnConflictUpdate(
      LocalProgressCompanion.insert(
        bookId: bookId,
        page: remote.page,
        completed: remote.completed,
        updatedAt: DateTime.now().toUtc(),
        serverLastModified: Value<DateTime?>(remote.lastModified.toUtc()),
      ),
    );
  }

  Future<void> forceAdopt(String bookId, ReadProgress? remote) async {
    if (remote == null) {
      await (delete(localProgress)..where((t) => t.bookId.equals(bookId))).go();
      return;
    }
    await into(localProgress).insertOnConflictUpdate(
      LocalProgressCompanion.insert(
        bookId: bookId,
        page: remote.page,
        completed: remote.completed,
        updatedAt: DateTime.now().toUtc(),
        serverLastModified: Value<DateTime?>(remote.lastModified.toUtc()),
        pendingSeq: const Value<int?>(null),
      ),
    );
  }

  // ---- 系列置顶（LIB-02 / ARC-06）----

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

  /// 整份替换指定服务器的置顶系列（备份导入用，保持传入顺序：排前面的时间戳更新）。
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

  // ---- 阅读会话历史（HIS-01 / ARC-06）----

  Future<int> addReadingSession({
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
    return into(readingSessions).insert(
      ReadingSessionsCompanion.insert(
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

  Future<List<ReadingSession>> readingSessionList({int limit = 200}) {
    return (select(readingSessions)
          ..orderBy(<OrderClauseGenerator<ReadingSessions>>[
            (ReadingSessions t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  Future<void> deleteReadingSession(int id) => (delete(
    readingSessions,
  )..where((ReadingSessions t) => t.id.equals(id))).go();

  Future<void> clearReadingSessions() => delete(readingSessions).go();
}
