/// 待提交的阅读进度。
class ProgressTarget {
  const ProgressTarget({
    required this.bookId,
    required this.page,
    required this.completed,
  });

  final String bookId;

  /// 1 基页码。
  final int page;

  final bool completed;

  @override
  bool operator ==(Object other) =>
      other is ProgressTarget &&
      other.bookId == bookId &&
      other.page == page &&
      other.completed == completed;

  @override
  int get hashCode => Object.hash(bookId, page, completed);

  @override
  String toString() =>
      'ProgressTarget($bookId, page: $page, completed: $completed)';
}

class PendingProgress {
  const PendingProgress(this.target, this.seq);

  final ProgressTarget target;

  /// 单调递增的入队序号，用于"提交期间又被更新"的竞态保护。
  final int seq;
}

/// 内存版 outbox。
///
/// 持久化版本（Drift）在 M4 实现，接口保持一致；这里先固化**语义**：
/// - 同一本书只保留最新一条（翻页会产生大量更新，必须合并）；
/// - 提交成功要带 seq 回执，避免把期间新入队的更新一起删掉；
/// - 顺序按入队先后，跨书互不影响。
class ProgressOutbox {
  final Map<String, PendingProgress> _pending = <String, PendingProgress>{};
  int _seq = 0;

  int get length => _pending.length;

  bool contains(String bookId) => _pending.containsKey(bookId);

  /// 按入队顺序返回待提交项。
  List<ProgressTarget> get pending {
    final items = _pending.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return List<ProgressTarget>.unmodifiable(items.map((e) => e.target));
  }

  PendingProgress? forBook(String bookId) => _pending[bookId];

  /// 入队并返回本次的序号。同书旧条目被覆盖。
  int enqueue(ProgressTarget target) {
    final seq = ++_seq;
    _pending[target.bookId] = PendingProgress(target, seq);
    return seq;
  }

  /// 提交成功后出队。
  ///
  /// [seq] 不匹配说明期间又有新进度入队，此时**不能**删除，否则会丢进度。
  bool markAcked(String bookId, int seq) {
    final current = _pending[bookId];
    if (current == null) return false;
    if (current.seq != seq) return false;
    _pending.remove(bookId);
    return true;
  }

  void clear() => _pending.clear();
}
