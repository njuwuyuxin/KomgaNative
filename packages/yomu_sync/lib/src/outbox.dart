import 'dart:math' as math;

import 'package:yomu_domain/yomu_domain.dart';

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

/// 单本书在本地存储中的进度与 outbox 合并快照（供内存与 Drift 存储共用同一套领域规则，P2-3）。
final class ProgressEntryState {
  const ProgressEntryState({
    required this.bookId,
    required this.page,
    required this.completed,
    required this.updatedAt,
    this.serverLastModified,
    this.pendingSeq,
  });

  final String bookId;
  final int page;
  final bool completed;
  final DateTime updatedAt;
  final DateTime? serverLastModified;
  final int? pendingSeq;

  bool get isPending => pendingSeq != null;
}

enum ProgressAdoptAction { keepLocal, delete, upsert }

/// 采纳服务端进度时的确定性落库计划。
final class ProgressAdoptPlan {
  const ProgressAdoptPlan._(this.action, this.entry);

  const ProgressAdoptPlan.keepLocal()
    : this._(ProgressAdoptAction.keepLocal, null);

  const ProgressAdoptPlan.delete() : this._(ProgressAdoptAction.delete, null);

  const ProgressAdoptPlan.upsert(ProgressEntryState entry)
    : this._(ProgressAdoptAction.upsert, entry);

  final ProgressAdoptAction action;
  final ProgressEntryState? entry;
}

/// Outbox 与本地进度的唯一领域规则真值源（P2-3）。
///
/// [ProgressOutbox]、[InMemoryProgressStore] 与生产环境 `DriftProgressStore`
/// 全部复用本组纯函数，确保测试与线上持久化共享完全一致的合并、排序、回执与对账语义。
abstract final class ProgressOutboxRules {
  /// 空 scope 统一经 [normalizeLegacySourceKey] 归一化，避免历史空串与本地分区出现双义。
  static String normalizeScope(String scope) =>
      normalizeLegacySourceKey(scope.trim());

  /// 生成严格单调递增的入队序号：同时大于历史最大序号与当前记录已有序号，
  /// 即使跨重启或系统时钟回拨也不会与旧待提交序号冲突。
  static int nextSequence({
    required int lastIssuedSeq,
    int? existingPendingSeq,
    int? floorHint,
  }) {
    final baseline = math.max(lastIssuedSeq, existingPendingSeq ?? 0);
    if (floorHint != null && floorHint > baseline) {
      return floorHint;
    }
    return baseline + 1;
  }

  /// 同书覆盖合并：保留最新页码/完成态、刷新 `updatedAt` 与新 `pendingSeq`，
  /// 同时保留既有的 `serverLastModified` 基准供多设备对账参考。
  static ProgressEntryState applyEnqueue({
    required ProgressTarget target,
    required ProgressEntryState? current,
    required int seq,
    required DateTime now,
  }) {
    return ProgressEntryState(
      bookId: target.bookId,
      page: target.page,
      completed: target.completed,
      updatedAt: now.toUtc(),
      serverLastModified: current?.serverLastModified?.toUtc(),
      pendingSeq: seq,
    );
  }

  /// 提交成功回执：仅当当前记录存在且 `pendingSeq == seq` 时清掉 pending 标记；
  /// 否则返回 `null`（提交期间又翻页，绝不能删掉更新的进度）。
  static ProgressEntryState? applyAck({
    required ProgressEntryState? current,
    required int seq,
  }) {
    if (current == null || current.pendingSeq != seq) return null;
    return ProgressEntryState(
      bookId: current.bookId,
      page: current.page,
      completed: current.completed,
      updatedAt: current.updatedAt.toUtc(),
      serverLastModified: null,
      pendingSeq: null,
    );
  }

  /// 采纳服务端进度决策：非强制模式下只要本地仍有待提交进度即保留本地；
  /// 否则远程为 `null` 时删除本地记录，有值时以服务端为准并清空 pending。
  static ProgressAdoptPlan planAdoptRemote({
    required String bookId,
    required ProgressEntryState? current,
    required ReadProgress? remote,
    required DateTime now,
    bool force = false,
  }) {
    if (!force && current?.pendingSeq != null) {
      return const ProgressAdoptPlan.keepLocal();
    }
    if (remote == null) {
      return const ProgressAdoptPlan.delete();
    }
    return ProgressAdoptPlan.upsert(
      ProgressEntryState(
        bookId: bookId,
        page: remote.page,
        completed: remote.completed,
        updatedAt: now.toUtc(),
        serverLastModified: remote.lastModified.toUtc(),
        pendingSeq: null,
      ),
    );
  }

  /// 按入队序号升序排列待提交项（相同序号时按 bookId 确定性排序）。
  static List<PendingProgress> sortPending(Iterable<PendingProgress> items) {
    final list = items.toList()
      ..sort((PendingProgress a, PendingProgress b) {
        final bySeq = a.seq.compareTo(b.seq);
        if (bySeq != 0) return bySeq;
        return a.target.bookId.compareTo(b.target.bookId);
      });
    return List<PendingProgress>.unmodifiable(list);
  }
}

/// 内存版 outbox（直接复用 [ProgressOutboxRules] 保持与持久化层零漂移）。
class ProgressOutbox {
  final Map<String, ProgressEntryState> _entries =
      <String, ProgressEntryState>{};
  int _seq = 0;

  int get length => _entries.length;

  bool contains(String bookId) => _entries.containsKey(bookId);

  /// 按入队顺序返回待提交项。
  List<ProgressTarget> get pending {
    final ordered = ProgressOutboxRules.sortPending(<PendingProgress>[
      for (final e in _entries.values)
        if (e.pendingSeq != null)
          PendingProgress(
            ProgressTarget(
              bookId: e.bookId,
              page: e.page,
              completed: e.completed,
            ),
            e.pendingSeq!,
          ),
    ]);
    return List<ProgressTarget>.unmodifiable(
      ordered.map((PendingProgress e) => e.target),
    );
  }

  PendingProgress? forBook(String bookId) {
    final entry = _entries[bookId];
    if (entry == null || entry.pendingSeq == null) return null;
    return PendingProgress(
      ProgressTarget(
        bookId: entry.bookId,
        page: entry.page,
        completed: entry.completed,
      ),
      entry.pendingSeq!,
    );
  }

  /// 入队并返回本次的序号。同书旧条目被覆盖。
  int enqueue(ProgressTarget target) {
    final current = _entries[target.bookId];
    final seq = ProgressOutboxRules.nextSequence(
      lastIssuedSeq: _seq,
      existingPendingSeq: current?.pendingSeq,
    );
    _seq = seq;
    _entries[target.bookId] = ProgressOutboxRules.applyEnqueue(
      target: target,
      current: current,
      seq: seq,
      now: DateTime.now().toUtc(),
    );
    return seq;
  }

  /// 提交成功后出队。
  ///
  /// [seq] 不匹配说明期间又有新进度入队，此时**不能**删除，否则会丢进度。
  bool markAcked(String bookId, int seq) {
    final next = ProgressOutboxRules.applyAck(
      current: _entries[bookId],
      seq: seq,
    );
    if (next == null) return false;
    _entries.remove(bookId);
    return true;
  }

  void clear() => _entries.clear();
}
