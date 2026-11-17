import 'dart:async';

import 'package:drift/drift.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

part 'progress_database.g.dart';

/// 本地进度 + 待提交队列（合一张表：一本书一行，pending 非空即可提交）。
///
/// 拆成两张表也能做，但会引入"提交成功后本地记录和 outbox 谁是真相"的一致性问题。
/// 一本书只有一条最新进度，合表后 `pending_seq` 就是唯一的状态位，简单且不会漂移。
class LocalProgress extends Table {
  TextColumn get bookId => text()();

  IntColumn get page => integer()();

  BoolColumn get completed => boolean()();

  /// 本地写入时间：只用于展示/诊断，**不参与对账**（设备墙钟不可信）。
  DateTimeColumn get updatedAt => dateTime()();

  /// 上次确认过的服务端 `lastModified`；PATCH 成功后置空（见 ADR 0002 决策 4）。
  DateTimeColumn get serverLastModified => dateTime().nullable()();

  /// 非空 = 有未提交更新；提交回执 seq 与它相等才清空。
  IntColumn get pendingSeq => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId};
}

@DriftDatabase(tables: <Type>[LocalProgress])
class ProgressDatabase extends _$ProgressDatabase {
  ProgressDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  /// 进程内的单调序号种子。
  ///
  /// 只用 `DateTime.now().microsecondsSinceEpoch` 不够：Windows/部分设备上
  /// 时钟精度只有毫秒级，两次快速入队可能拿到同一个值，ack 就会误清新进度。
  int _seqSeed = 0;

  /// 入队并返回本次的 seq。
  ///
  /// seq 取写入时刻的微秒并保证**严格递增**；同书只保留最新一条。
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
        // 新进度还没提交，服务端基准暂不更新，保留上一次已知的值。
      ),
    );
    return seq;
  }

  /// 提交成功后的回执。
  ///
  /// 只有 seq 仍然匹配才清空：期间又翻页的话（seq 更大）必须保留新进度。
  /// 返回 true 表示这条进度已经从队列里清掉。
  Future<bool> ack(String bookId, int seq) async {
    final updated =
        await (update(localProgress)..where(
              (LocalProgress t) =>
                  t.bookId.equals(bookId) & t.pendingSeq.equals(seq),
            ))
            .write(
              const LocalProgressCompanion(
                pendingSeq: Value<int?>(null),
                // PATCH 没有响应体，拿不到服务端新的 lastModified；
                // 置空 → 下次 GET 时按 adoptRemote 重新建立基准。
                serverLastModified: Value<DateTime?>(null),
              ),
            );
    return updated > 0;
  }

  Future<LocalProgressData?> record(String bookId) => (select(
    localProgress,
  )..where((t) => t.bookId.equals(bookId))).getSingleOrNull();

  /// 批量读：书架一页 100 本，不能一本一次查询。
  Future<List<LocalProgressData>> records(List<String> bookIds) async {
    if (bookIds.isEmpty) return const <LocalProgressData>[];
    return (select(localProgress)..where((t) => t.bookId.isIn(bookIds))).get();
  }

  /// 所有待提交项，按 seq 升序（先入队先提交）。
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

  /// 采纳服务端进度（别的设备读得更远 / 本地首次见到）。
  ///
  /// 有 pending 时**不写**：本地还有没提交的更新，服务端的旧值不能覆盖它。
  Future<void> adoptRemote(String bookId, ReadProgress? remote) async {
    final current = await record(bookId);
    if (current?.pendingSeq != null) return;

    if (remote == null) {
      // 服务端把进度删了（标记未读）：本地也清掉。
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
}
