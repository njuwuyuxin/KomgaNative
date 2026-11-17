import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_database.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

/// 本地已知的阅读进度。
///
/// 与 [ReadProgress] 的区别：这里**不假装知道服务端时间**——
/// [serverLastModified] 是上次确认过的服务端值（可能没有），
/// [updatedAt] 只是本地写入时间，不能拿去对账。
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

  /// 给 UI 用的进度。
  ///
  /// `lastModified` 优先用服务端时间；没有就用本地写入时间（只用于展示/排序，
  /// 万一被当成对账基准交给 `decideSync`，调用方拿的是 [serverLastModified]）。
  ReadProgress toReadProgress() => ReadProgress(
    page: page,
    completed: completed,
    lastModified: serverLastModified ?? updatedAt,
  );
}

/// 进度持久化的抽象。
///
/// 真实现是 Drift（见 [DriftProgressStore]）；测试用内存实现，
/// 这样 outbox 的语义（合并/回执/对账）可以在毫秒级单测里覆盖。
abstract interface class ProgressStore {
  Future<ProgressRecord?> record(String bookId);

  /// 批量读（书架一页 100 本，不能一本一次查询）。
  Future<Map<String, ProgressRecord>> records(Iterable<String> bookIds);

  Future<void> enqueue(ProgressTarget target);

  Future<List<PendingProgress>> pending();

  /// 提交成功回执；seq 不匹配（期间又翻页）时返回 false 且不清空。
  Future<bool> ack(String bookId, int seq);

  /// 采纳服务端进度（有 pending 时不写）。
  Future<void> adoptRemote(String bookId, ReadProgress? remote);

  /// **强制**采纳服务端进度：清掉本地 pending 后写入。
  ///
  /// 只用于"用户显式改了阅读状态"（标记已读/未读）——此时本地那份未提交进度
  /// 已经过期，继续保留会让界面显示"我刚标记未读，但书架还是读过"。
  Future<void> forceAdopt(String bookId, ReadProgress? remote);
}

class DriftProgressStore implements ProgressStore {
  DriftProgressStore(this._db);

  final ProgressDatabase _db;

  @override
  Future<ProgressRecord?> record(String bookId) async {
    final row = await _db.record(bookId);
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<Map<String, ProgressRecord>> records(Iterable<String> bookIds) async {
    final ids = bookIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, ProgressRecord>{};
    final rows = await _db.records(ids);
    return <String, ProgressRecord>{
      for (final row in rows) row.bookId: _toRecord(row),
    };
  }

  @override
  Future<void> enqueue(ProgressTarget target) => _db.enqueue(target);

  @override
  Future<List<PendingProgress>> pending() => _db.pending();

  @override
  Future<bool> ack(String bookId, int seq) => _db.ack(bookId, seq);

  @override
  Future<void> adoptRemote(String bookId, ReadProgress? remote) =>
      _db.adoptRemote(bookId, remote);

  @override
  Future<void> forceAdopt(String bookId, ReadProgress? remote) =>
      _db.forceAdopt(bookId, remote);

  static ProgressRecord _toRecord(LocalProgressData row) => ProgressRecord(
    page: row.page,
    completed: row.completed,
    // Drift 默认把 DateTime 存成 Unix 秒、按本地时区读回；统一转 UTC，
    // 避免"服务端时间"和"本地时间"在比较时混掉时区语义。
    updatedAt: row.updatedAt.toUtc(),
    serverLastModified: row.serverLastModified?.toUtc(),
    pendingSeq: row.pendingSeq,
  );
}

/// 测试/预览用：语义与 Drift 实现一致的纯内存版本。
///
/// 单独写一份而不是"直接测 Drift"，是为了让 outbox 的规则（合并、回执竞态）
/// 在不需要数据库的情况下也能覆盖；Drift 实现另有自己的用例。
class InMemoryProgressStore implements ProgressStore {
  final Map<String, ProgressRecord> _records = <String, ProgressRecord>{};
  int _seq = 0;

  @override
  Future<ProgressRecord?> record(String bookId) async => _records[bookId];

  @override
  Future<Map<String, ProgressRecord>> records(Iterable<String> bookIds) async =>
      <String, ProgressRecord>{
        for (final id in bookIds)
          if (_records[id] != null) id: _records[id]!,
      };

  @override
  Future<void> enqueue(ProgressTarget target) async {
    _seq++;
    _records[target.bookId] = ProgressRecord(
      page: target.page,
      completed: target.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: _records[target.bookId]?.serverLastModified,
      pendingSeq: _seq,
    );
  }

  @override
  Future<List<PendingProgress>> pending() async {
    final items =
        _records.entries.where((MapEntry<String, ProgressRecord> e) {
          return e.value.isPending;
        }).toList()..sort(
          (
            MapEntry<String, ProgressRecord> a,
            MapEntry<String, ProgressRecord> b,
          ) => a.value.pendingSeq!.compareTo(b.value.pendingSeq!),
        );
    return <PendingProgress>[
      for (final entry in items)
        PendingProgress(
          ProgressTarget(
            bookId: entry.key,
            page: entry.value.page,
            completed: entry.value.completed,
          ),
          entry.value.pendingSeq!,
        ),
    ];
  }

  @override
  Future<bool> ack(String bookId, int seq) async {
    final current = _records[bookId];
    if (current == null || current.pendingSeq != seq) return false;
    _records[bookId] = ProgressRecord(
      page: current.page,
      completed: current.completed,
      updatedAt: current.updatedAt,
      // PATCH 无响应体：基准置空，等下次 GET 重新建立（与 Drift 实现一致）。
      serverLastModified: null,
      pendingSeq: null,
    );
    return true;
  }

  @override
  Future<void> adoptRemote(String bookId, ReadProgress? remote) async {
    final current = _records[bookId];
    if (current?.isPending ?? false) return;
    if (remote == null) {
      _records.remove(bookId);
      return;
    }
    _records[bookId] = ProgressRecord(
      page: remote.page,
      completed: remote.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: remote.lastModified.toUtc(),
    );
  }

  @override
  Future<void> forceAdopt(String bookId, ReadProgress? remote) async {
    if (remote == null) {
      _records.remove(bookId);
      return;
    }
    _records[bookId] = ProgressRecord(
      page: remote.page,
      completed: remote.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: remote.lastModified.toUtc(),
    );
  }
}
