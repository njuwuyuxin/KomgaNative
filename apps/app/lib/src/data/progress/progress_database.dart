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
  int get schemaVersion => 7;

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
      if (from < 7) {
        await _backfillEmptyScopesToV7();
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await _migrateFromLegacyCacheIfNeeded();
    },
  );

  int _seqSeed = 0;

  static ProgressEntryState _toEntryState(LocalProgressData row) =>
      ProgressEntryState(
        bookId: row.bookId,
        page: row.page,
        completed: row.completed,
        updatedAt: row.updatedAt.toUtc(),
        serverLastModified: row.serverLastModified?.toUtc(),
        pendingSeq: row.pendingSeq,
      );

  static LocalProgressCompanion _toCompanion(
    String scope,
    ProgressEntryState entry,
  ) => LocalProgressCompanion.insert(
    scope: Value<String>(scope),
    bookId: entry.bookId,
    page: entry.page,
    completed: entry.completed,
    updatedAt: entry.updatedAt.toUtc(),
    serverLastModified: Value<DateTime?>(entry.serverLastModified?.toUtc()),
    pendingSeq: Value<int?>(entry.pendingSeq),
  );

  Future<int> enqueue(
    ProgressTarget target, {
    String scope = kLocalSourceKey,
  }) async {
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    return transaction<int>(() async {
      final currentRow = await record(target.bookId, scope: normalizedScope);
      final current = currentRow == null ? null : _toEntryState(currentRow);
      final now = DateTime.now().toUtc();
      final seq = ProgressOutboxRules.nextSequence(
        lastIssuedSeq: _seqSeed,
        existingPendingSeq: current?.pendingSeq,
        floorHint: now.microsecondsSinceEpoch,
      );
      _seqSeed = seq;
      final next = ProgressOutboxRules.applyEnqueue(
        target: target,
        current: current,
        seq: seq,
        now: now,
      );
      await into(localProgress)
          .insertOnConflictUpdate(_toCompanion(normalizedScope, next));
      return seq;
    });
  }

  Future<bool> ack(
    String bookId,
    int seq, {
    String scope = kLocalSourceKey,
  }) async {
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    return transaction<bool>(() async {
      final currentRow = await record(bookId, scope: normalizedScope);
      final next = ProgressOutboxRules.applyAck(
        current: currentRow == null ? null : _toEntryState(currentRow),
        seq: seq,
      );
      if (next == null) return false;
      await into(localProgress)
          .insertOnConflictUpdate(_toCompanion(normalizedScope, next));
      return true;
    });
  }

  Future<LocalProgressData?> record(
    String bookId, {
    String scope = kLocalSourceKey,
  }) {
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    return (select(localProgress)..where(
          (t) => t.scope.equals(normalizedScope) & t.bookId.equals(bookId),
        ))
        .getSingleOrNull();
  }

  Future<List<LocalProgressData>> records(
    List<String> bookIds, {
    String scope = kLocalSourceKey,
  }) async {
    if (bookIds.isEmpty) return const <LocalProgressData>[];
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    return (select(localProgress)..where(
          (t) => t.scope.equals(normalizedScope) & t.bookId.isIn(bookIds),
        ))
        .get();
  }

  Future<List<PendingProgress>> pending({
    String scope = kLocalSourceKey,
  }) async {
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    final rows =
        await (select(localProgress)..where(
              (t) => t.scope.equals(normalizedScope) & t.pendingSeq.isNotNull(),
            ))
            .get();
    return ProgressOutboxRules.sortPending(<PendingProgress>[
      for (final row in rows)
        PendingProgress(
          ProgressTarget(
            bookId: row.bookId,
            page: row.page,
            completed: row.completed,
          ),
          row.pendingSeq!,
        ),
    ]);
  }

  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  }) => _applyAdoptRemote(bookId, remote, scope: scope, force: false);

  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  }) => _applyAdoptRemote(bookId, remote, scope: scope, force: true);

  Future<void> _applyAdoptRemote(
    String bookId,
    ReadProgress? remote, {
    required String scope,
    required bool force,
  }) async {
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    await transaction<void>(() async {
      final currentRow = await record(bookId, scope: normalizedScope);
      final plan = ProgressOutboxRules.planAdoptRemote(
        bookId: bookId,
        current: currentRow == null ? null : _toEntryState(currentRow),
        remote: remote,
        now: DateTime.now().toUtc(),
        force: force,
      );
      switch (plan.action) {
        case ProgressAdoptAction.keepLocal:
          return;
        case ProgressAdoptAction.delete:
          await (delete(localProgress)..where(
                (t) =>
                    t.scope.equals(normalizedScope) & t.bookId.equals(bookId),
              ))
              .go();
        case ProgressAdoptAction.upsert:
          await into(
            localProgress,
          ).insertOnConflictUpdate(_toCompanion(normalizedScope, plan.entry!));
      }
    });
  }

  Future<int> clearProgressScope(String scope) {
    final normalizedScope = ProgressOutboxRules.normalizeScope(scope);
    return (delete(
      localProgress,
    )..where((t) => t.scope.equals(normalizedScope))).go();
  }
}
