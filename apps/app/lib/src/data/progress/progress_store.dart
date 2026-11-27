import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_sync/yomu_sync.dart';

/// 本地已知的阅读进度。
class ProgressRecord {
  const ProgressRecord({
    required this.page,
    required this.completed,
    required this.updatedAt,
    this.serverLastModified,
    this.pendingSeq,
  });

  final int page;
  final bool completed;
  final DateTime updatedAt;
  final DateTime? serverLastModified;
  final int? pendingSeq;

  bool get isPending => pendingSeq != null;

  ReadProgress toReadProgress() => ReadProgress(
    page: page,
    completed: completed,
    lastModified: serverLastModified ?? updatedAt,
  );
}

/// 进度持久化的抽象（按服务器 `scope` 分区，ARC-07 / P2-3）。
abstract interface class ProgressStore {
  Future<ProgressRecord?> record(
    String bookId, {
    String scope = kLocalSourceKey,
  });

  /// 批量读（书架一页 100 本，不能一本一次查询）。
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = kLocalSourceKey,
  });

  Future<void> enqueue(ProgressTarget target, {String scope = kLocalSourceKey});

  Future<List<PendingProgress>> pending({String scope = kLocalSourceKey});

  /// 提交成功回执；seq 不匹配（期间又翻页）时返回 false 且不清空。
  Future<bool> ack(String bookId, int seq, {String scope = kLocalSourceKey});

  /// 采纳服务端进度（有 pending 时不写）。
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  });

  /// **强制**采纳服务端进度：清掉本地 pending 后写入。
  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  });

  /// 删除整个分区的进度与待提交 outbox 记录（用于删除服务器后的彻底清理）。
  Future<void> clearScope(String scope);
}

class DriftProgressStore implements ProgressStore {
  DriftProgressStore(this._db);

  final ProgressDatabase _db;

  @override
  Future<ProgressRecord?> record(
    String bookId, {
    String scope = kLocalSourceKey,
  }) async {
    final row = await _db.record(bookId, scope: scope);
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = kLocalSourceKey,
  }) async {
    final ids = bookIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, ProgressRecord>{};
    final rows = await _db.records(ids, scope: scope);
    return <String, ProgressRecord>{
      for (final row in rows) row.bookId: _toRecord(row),
    };
  }

  @override
  Future<void> enqueue(
    ProgressTarget target, {
    String scope = kLocalSourceKey,
  }) => _db.enqueue(target, scope: scope);

  @override
  Future<List<PendingProgress>> pending({String scope = kLocalSourceKey}) =>
      _db.pending(scope: scope);

  @override
  Future<bool> ack(String bookId, int seq, {String scope = kLocalSourceKey}) =>
      _db.ack(bookId, seq, scope: scope);

  @override
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  }) => _db.adoptRemote(bookId, remote, scope: scope);

  @override
  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  }) => _db.forceAdopt(bookId, remote, scope: scope);

  @override
  Future<void> clearScope(String scope) async {
    await _db.clearProgressScope(scope);
  }

  static ProgressRecord _toRecord(LocalProgressData row) => ProgressRecord(
    page: row.page,
    completed: row.completed,
    updatedAt: row.updatedAt.toUtc(),
    serverLastModified: row.serverLastModified?.toUtc(),
    pendingSeq: row.pendingSeq,
  );
}

/// 测试/预览用：按 `{scope, bookId}` 分区的纯内存版本，
/// 与 [DriftProgressStore] 共用同一套 [ProgressOutboxRules]（P2-3）。
class InMemoryProgressStore implements ProgressStore {
  final Map<String, Map<String, ProgressEntryState>> _byScope =
      <String, Map<String, ProgressEntryState>>{};
  int _seqSeed = 0;

  Map<String, ProgressEntryState> _bucket(String scope) {
    final normalized = ProgressOutboxRules.normalizeScope(scope);
    return _byScope.putIfAbsent(
      normalized,
      () => <String, ProgressEntryState>{},
    );
  }

  static ProgressRecord _toRecord(ProgressEntryState entry) => ProgressRecord(
    page: entry.page,
    completed: entry.completed,
    updatedAt: entry.updatedAt.toUtc(),
    serverLastModified: entry.serverLastModified?.toUtc(),
    pendingSeq: entry.pendingSeq,
  );

  @override
  Future<ProgressRecord?> record(
    String bookId, {
    String scope = kLocalSourceKey,
  }) async {
    final normalized = ProgressOutboxRules.normalizeScope(scope);
    final entry = _byScope[normalized]?[bookId];
    return entry == null ? null : _toRecord(entry);
  }

  @override
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = kLocalSourceKey,
  }) async {
    final normalized = ProgressOutboxRules.normalizeScope(scope);
    final bucket = _byScope[normalized];
    if (bucket == null) return const <String, ProgressRecord>{};
    final result = <String, ProgressRecord>{};
    for (final id in bookIds) {
      final entry = bucket[id];
      if (entry != null) result[id] = _toRecord(entry);
    }
    return result;
  }

  @override
  Future<void> enqueue(
    ProgressTarget target, {
    String scope = kLocalSourceKey,
  }) async {
    final bucket = _bucket(scope);
    final current = bucket[target.bookId];
    final now = DateTime.now().toUtc();
    final seq = ProgressOutboxRules.nextSequence(
      lastIssuedSeq: _seqSeed,
      existingPendingSeq: current?.pendingSeq,
      floorHint: now.microsecondsSinceEpoch,
    );
    _seqSeed = seq;
    bucket[target.bookId] = ProgressOutboxRules.applyEnqueue(
      target: target,
      current: current,
      seq: seq,
      now: now,
    );
  }

  @override
  Future<List<PendingProgress>> pending({
    String scope = kLocalSourceKey,
  }) async {
    final normalized = ProgressOutboxRules.normalizeScope(scope);
    final bucket = _byScope[normalized];
    if (bucket == null) return const <PendingProgress>[];
    return ProgressOutboxRules.sortPending(<PendingProgress>[
      for (final entry in bucket.values)
        if (entry.pendingSeq != null)
          PendingProgress(
            ProgressTarget(
              bookId: entry.bookId,
              page: entry.page,
              completed: entry.completed,
            ),
            entry.pendingSeq!,
          ),
    ]);
  }

  @override
  Future<bool> ack(
    String bookId,
    int seq, {
    String scope = kLocalSourceKey,
  }) async {
    final normalized = ProgressOutboxRules.normalizeScope(scope);
    final bucket = _byScope[normalized];
    if (bucket == null) return false;
    final next = ProgressOutboxRules.applyAck(
      current: bucket[bookId],
      seq: seq,
    );
    if (next == null) return false;
    bucket[bookId] = next;
    return true;
  }

  @override
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = kLocalSourceKey,
  }) => _applyAdoptRemote(bookId, remote, scope: scope, force: false);

  @override
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
    final bucket = _bucket(scope);
    final plan = ProgressOutboxRules.planAdoptRemote(
      bookId: bookId,
      current: bucket[bookId],
      remote: remote,
      now: DateTime.now().toUtc(),
      force: force,
    );
    switch (plan.action) {
      case ProgressAdoptAction.keepLocal:
        return;
      case ProgressAdoptAction.delete:
        bucket.remove(bookId);
      case ProgressAdoptAction.upsert:
        bucket[bookId] = plan.entry!;
    }
  }

  @override
  Future<void> clearScope(String scope) async {
    _byScope.remove(ProgressOutboxRules.normalizeScope(scope));
  }
}
