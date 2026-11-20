import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_database.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

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

/// 测试/预览用：按 `{scope, bookId}` 分区的纯内存版本。
class InMemoryProgressStore implements ProgressStore {
  final Map<String, Map<String, ProgressRecord>> _byScope =
      <String, Map<String, ProgressRecord>>{};
  int _seq = 0;

  Map<String, ProgressRecord> _bucket(String scope) =>
      _byScope.putIfAbsent(scope, () => <String, ProgressRecord>{});

  @override
  Future<ProgressRecord?> record(String bookId, {String scope = ''}) async =>
      _byScope[scope]?[bookId];

  @override
  Future<Map<String, ProgressRecord>> records(
    Iterable<String> bookIds, {
    String scope = '',
  }) async {
    final map = _byScope[scope];
    if (map == null) return const <String, ProgressRecord>{};
    return <String, ProgressRecord>{
      for (final id in bookIds)
        if (map[id] != null) id: map[id]!,
    };
  }

  @override
  Future<void> enqueue(ProgressTarget target, {String scope = ''}) async {
    _seq++;
    final map = _bucket(scope);
    map[target.bookId] = ProgressRecord(
      page: target.page,
      completed: target.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: map[target.bookId]?.serverLastModified,
      pendingSeq: _seq,
    );
  }

  @override
  Future<List<PendingProgress>> pending({String scope = ''}) async {
    final map = _byScope[scope];
    if (map == null) return const <PendingProgress>[];
    final items =
        map.entries.where((MapEntry<String, ProgressRecord> e) {
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
  Future<bool> ack(String bookId, int seq, {String scope = ''}) async {
    final map = _byScope[scope];
    final current = map?[bookId];
    if (current == null || current.pendingSeq != seq) return false;
    map![bookId] = ProgressRecord(
      page: current.page,
      completed: current.completed,
      updatedAt: current.updatedAt,
      serverLastModified: null,
      pendingSeq: null,
    );
    return true;
  }

  @override
  Future<void> adoptRemote(
    String bookId,
    ReadProgress? remote, {
    String scope = '',
  }) async {
    final map = _bucket(scope);
    final current = map[bookId];
    if (current?.isPending ?? false) return;
    if (remote == null) {
      map.remove(bookId);
      return;
    }
    map[bookId] = ProgressRecord(
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
    final map = _bucket(scope);
    if (remote == null) {
      map.remove(bookId);
      return;
    }
    map[bookId] = ProgressRecord(
      page: remote.page,
      completed: remote.completed,
      updatedAt: DateTime.now().toUtc(),
      serverLastModified: remote.lastModified.toUtc(),
    );
  }
}
