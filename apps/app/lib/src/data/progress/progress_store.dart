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

/// 进度持久化的抽象（按服务器 `scope` 分区，ARC-07）。
abstract interface class ProgressStore {
  Future<ProgressRecord?> record(String bookId, {String scope = ''});

  /// 批量读（书架一页 100 本，不能一本一次查询）。
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = '',
  });

  Future<void> enqueue(ProgressTarget target, {String scope = ''});

  Future<List<PendingProgress>> pending({String scope = ''});

  /// 提交成功回执；seq 不匹配（期间又翻页）时返回 false 且不清空。
  Future<bool> ack(String bookId, int seq, {String scope = ''});

  /// 采纳服务端进度（有 pending 时不写）。
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  });

  /// **强制**采纳服务端进度：清掉本地 pending 后写入。
  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  });
}

class DriftProgressStore implements ProgressStore {
  DriftProgressStore(this._db);

  final ProgressDatabase _db;

  @override
  Future<ProgressRecord?> record(String bookId, {String scope = ''}) async {
    final row = await _db.record(bookId, scope: scope);
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = '',
  }) async {
    final ids = bookIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, ProgressRecord>{};
    final rows = await _db.records(ids, scope: scope);
    return <String, ProgressRecord>{
      for (final row in rows) row.bookId: _toRecord(row),
    };
  }

  @override
  Future<void> enqueue(ProgressTarget target, {String scope = ''}) =>
      _db.enqueue(target, scope: scope);

  @override
  Future<List<PendingProgress>> pending({String scope = ''}) =>
      _db.pending(scope: scope);

  @override
  Future<bool> ack(String bookId, int seq, {String scope = ''}) =>
      _db.ack(bookId, seq, scope: scope);

  @override
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) => _db.adoptRemote(bookId, remote, scope: scope);

  @override
  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) => _db.forceAdopt(bookId, remote, scope: scope);

  static ProgressRecord _toRecord(LocalProgressData row) => ProgressRecord(
    page: row.page,
    completed: row.completed,
    updatedAt: row.updatedAt.toUtc(),
    serverLastModified: row.serverLastModified?.toUtc(),
    pendingSeq: row.pendingSeq,
  );
}

/// 测试/预览用：按 `{scope, bookId}` 分区的纯内存版本，内部委托复用 [ProgressOutbox]（ARC-11）。
class InMemoryProgressStore implements ProgressStore {
  final Map<String, _ScopedMemoryBucket> _byScope =
      <String, _ScopedMemoryBucket>{};

  _ScopedMemoryBucket _bucket(String scope) =>
      _byScope.putIfAbsent(scope, _ScopedMemoryBucket.new);

  ProgressRecord? _mergedRecord(_ScopedMemoryBucket bucket, String bookId) {
    final base = bucket.records[bookId];
    final pending = bucket.outbox.forBook(bookId);
    if (pending != null) {
      return ProgressRecord(
        page: pending.target.page,
        completed: pending.target.completed,
        updatedAt: base?.updatedAt ?? DateTime.now().toUtc(),
        serverLastModified: base?.serverLastModified,
        pendingSeq: pending.seq,
      );
    }
    return base;
  }

  @override
  Future<ProgressRecord?> record(String bookId, {String scope = ''}) async {
    final bucket = _byScope[scope];
    if (bucket == null) return null;
    return _mergedRecord(bucket, bookId);
  }

  @override
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = '',
  }) async {
    final bucket = _byScope[scope];
    if (bucket == null) return const <String, ProgressRecord>{};
    final result = <String, ProgressRecord>{};
    for (final id in bookIds) {
      final rec = _mergedRecord(bucket, id);
      if (rec != null) result[id] = rec;
    }
    return result;
  }

  @override
  Future<void> enqueue(ProgressTarget target, {String scope = ''}) async {
    final bucket = _bucket(scope);
    final seq = bucket.outbox.enqueue(target);
    bucket.records[target.bookId] = ProgressRecord(
      page: target.page,
      completed: target.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: bucket.records[target.bookId]?.serverLastModified,
      pendingSeq: seq,
    );
  }

  @override
  Future<List<PendingProgress>> pending({String scope = ''}) async {
    final bucket = _byScope[scope];
    if (bucket == null) return const <PendingProgress>[];
    return <PendingProgress>[
      for (final target in bucket.outbox.pending)
        bucket.outbox.forBook(target.bookId)!,
    ];
  }

  @override
  Future<bool> ack(String bookId, int seq, {String scope = ''}) async {
    final bucket = _byScope[scope];
    if (bucket == null || !bucket.outbox.markAcked(bookId, seq)) return false;
    final current = bucket.records[bookId];
    if (current != null) {
      bucket.records[bookId] = ProgressRecord(
        page: current.page,
        completed: current.completed,
        updatedAt: current.updatedAt,
        serverLastModified: null,
        pendingSeq: null,
      );
    }
    return true;
  }

  @override
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) async {
    final bucket = _bucket(scope);
    if (bucket.outbox.contains(bookId)) return;
    if (remote == null) {
      bucket.records.remove(bookId);
      return;
    }
    bucket.records[bookId] = ProgressRecord(
      page: remote.page,
      completed: remote.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: remote.lastModified.toUtc(),
    );
  }

  @override
  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) async {
    final bucket = _bucket(scope);
    final pending = bucket.outbox.forBook(bookId);
    if (pending != null) {
      bucket.outbox.markAcked(bookId, pending.seq);
    }
    if (remote == null) {
      bucket.records.remove(bookId);
      return;
    }
    bucket.records[bookId] = ProgressRecord(
      page: remote.page,
      completed: remote.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: remote.lastModified.toUtc(),
    );
  }
}

class _ScopedMemoryBucket {
  final ProgressOutbox outbox = ProgressOutbox();
  final Map<String, ProgressRecord> records = <String, ProgressRecord>{};
}
