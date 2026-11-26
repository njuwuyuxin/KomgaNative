import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yomu/src/data/local/local_tables.dart';
import 'package:yomu/src/data/progress/user_tables.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

export 'package:yomu/src/data/local/local_tables.dart';
export 'package:yomu/src/data/progress/user_tables.dart';

part 'progress_database.g.dart';
part 'progress_user_dao.dart';

/// 用户本地资产数据库（`komga_native.sqlite`）：阅读进度、置顶、阅读会话与本机漫画目录。
@DriftDatabase(
  tables: <Type>[
    LocalProgress,
    PinnedSeriesRows,
    ReadingSessions,
    LocalSeriesRows,
    LocalBooksRows,
    LocalPagesRows,
    LocalBookChaptersRows,
    LocalMountedRootsRows,
    LocalCollectionsRows,
    LocalReadListsRows,
    PageBookmarksRows,
  ],
)
class ProgressDatabase extends _$ProgressDatabase {
  ProgressDatabase(
    super.executor, {
    this.legacyCacheDbPath,
    this.defaultLegacyScope,
  });

  final FutureOr<String?> Function()? legacyCacheDbPath;
  final FutureOr<String> Function()? defaultLegacyScope;

  @override
  int get schemaVersion => 6;

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
      if (from < 3) {
        final rawScope = await defaultLegacyScope?.call() ?? '';
        final escaped = rawScope.replaceAll("'", "''");
        await _upgradeLocalProgressToV3(escaped);
        if (from >= 2) {
          await m.addColumn(readingSessions, readingSessions.scope);
        }
        if (escaped.isNotEmpty) {
          await customStatement(
            "UPDATE reading_sessions SET scope = '$escaped' WHERE scope = ''",
          );
        }
      }
      if (from < 4) {
        await m.createTable(localSeriesRows);
        await m.createTable(localBooksRows);
        await m.createTable(localPagesRows);
        await m.createTable(localCollectionsRows);
        await m.createTable(localReadListsRows);
      }
      if (from < 5) {
        await m.createTable(localBookChaptersRows);
        await m.createTable(pageBookmarksRows);
      }
      if (from < 6) {
        await m.createTable(localMountedRootsRows);
        if (from >= 4) {
          await m.addColumn(localBooksRows, localBooksRows.mountRootId);
          await m.addColumn(localBooksRows, localBooksRows.sourceRelativePath);
          await m.addColumn(localBooksRows, localBooksRows.sourceModifiedMs);
          await m.addColumn(localBooksRows, localBooksRows.isCloudPlaceholder);
        }
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await _migrateFromLegacyCacheIfNeeded();
    },
  );

  int _seqSeed = 0;

  Future<int> enqueue(ProgressTarget target, {String scope = ''}) async {
    final now = DateTime.now().toUtc();
    final micros = now.microsecondsSinceEpoch;
    final seq = micros > _seqSeed ? micros : _seqSeed + 1;
    _seqSeed = seq;
    await into(localProgress).insertOnConflictUpdate(
      LocalProgressCompanion.insert(
        scope: Value<String>(scope),
        bookId: target.bookId,
        page: target.page,
        completed: target.completed,
        updatedAt: now,
        pendingSeq: Value<int>(seq),
      ),
    );
    return seq;
  }

  Future<bool> ack(String bookId, int seq, {String scope = ''}) async {
    final updated =
        await (update(localProgress)..where(
              (LocalProgress t) =>
                  t.scope.equals(scope) &
                  t.bookId.equals(bookId) &
                  t.pendingSeq.equals(seq),
            ))
            .write(
              const LocalProgressCompanion(
                pendingSeq: Value<int?>(null),
                serverLastModified: Value<DateTime?>(null),
              ),
            );
    return updated > 0;
  }

  Future<LocalProgressData?> record(String bookId, {String scope = ''}) =>
      (select(localProgress)
            ..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId)))
          .getSingleOrNull();

  Future<List<LocalProgressData>> records(
    List<String> bookIds, {
    String scope = '',
  }) async {
    if (bookIds.isEmpty) return const <LocalProgressData>[];
    return (select(
      localProgress,
    )..where((t) => t.scope.equals(scope) & t.bookId.isIn(bookIds))).get();
  }

  Future<List<PendingProgress>> pending({String scope = ''}) async {
    final rows =
        await (select(localProgress)
              ..where((t) => t.scope.equals(scope) & t.pendingSeq.isNotNull())
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

  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) async {
    final current = await record(bookId, scope: scope);
    if (current?.pendingSeq != null) return;

    if (remote == null) {
      await (delete(
        localProgress,
      )..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))).go();
      return;
    }
    await into(localProgress).insertOnConflictUpdate(
      LocalProgressCompanion.insert(
        scope: Value<String>(scope),
        bookId: bookId,
        page: remote.page,
        completed: remote.completed,
        updatedAt: DateTime.now().toUtc(),
        serverLastModified: Value<DateTime?>(remote.lastModified.toUtc()),
      ),
    );
  }

  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) async {
    if (remote == null) {
      await (delete(
        localProgress,
      )..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))).go();
      return;
    }
    await into(localProgress).insertOnConflictUpdate(
      LocalProgressCompanion.insert(
        scope: Value<String>(scope),
        bookId: bookId,
        page: remote.page,
        completed: remote.completed,
        updatedAt: DateTime.now().toUtc(),
        serverLastModified: Value<DateTime?>(remote.lastModified.toUtc()),
        pendingSeq: const Value<int?>(null),
      ),
    );
  }
}
