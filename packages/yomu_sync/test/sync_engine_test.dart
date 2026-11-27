import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';
import 'package:test/test.dart';

void main() {
  ProgressTarget target(String book, int page, {bool completed = false}) =>
      ProgressTarget(bookId: book, page: page, completed: completed);

  group('ProgressOutbox', () {
    test('同书只保留最新一条，且入队序号单调递增', () {
      final outbox = ProgressOutbox();
      final s1 = outbox.enqueue(target('b1', 3));
      final s2 = outbox.enqueue(target('b1', 7));
      expect(s2, greaterThan(s1));
      expect(outbox.length, 1);
      expect(outbox.forBook('b1')!.target.page, 7);
    });

    test('跨书按入队顺序返回（决定提交顺序）', () {
      final outbox = ProgressOutbox();
      outbox.enqueue(target('b1', 3));
      outbox.enqueue(target('b2', 1));
      outbox.enqueue(target('b1', 4)); // b1 更新但序号变大
      expect(outbox.pending.map((e) => e.bookId).toList(), ['b2', 'b1']);
      expect(outbox.pending.last.page, 4);
    });

    test('提交期间又翻页：旧回执不能删掉新进度', () {
      final outbox = ProgressOutbox();
      final seq = outbox.enqueue(target('b1', 5));
      outbox.enqueue(target('b1', 6)); // 提交还没回来，用户又翻了一页
      expect(outbox.markAcked('b1', seq), isFalse);
      expect(outbox.forBook('b1')!.target.page, 6);
      expect(outbox.markAcked('b1', outbox.forBook('b1')!.seq), isTrue);
      expect(outbox.length, 0);
    });

    test('回执未知书籍返回 false，不抛异常', () {
      final outbox = ProgressOutbox();
      expect(outbox.markAcked('nope', 1), isFalse);
    });

    test('pending 返回不可变列表', () {
      final outbox = ProgressOutbox()..enqueue(target('b1', 1));
      expect(() => outbox.pending.add(target('b2', 1)), throwsUnsupportedError);
    });
  });

  group('ProgressOutboxRules（P2-3 唯一真值规则）', () {
    final t0 = DateTime.utc(2026, 11, 20, 10);
    final t1 = t0.add(const Duration(minutes: 2));

    test('nextSequence 在时钟回拨或跨重启遇到更大已有 seq 时仍严格递增', () {
      final seq = ProgressOutboxRules.nextSequence(
        lastIssuedSeq: 100,
        existingPendingSeq: 5000,
        floorHint: 200, // 模拟时钟回拨到小于已持久化的 pendingSeq
      );
      expect(seq, 5001);
    });

    test('applyEnqueue 合并同书更新时保留 serverLastModified 基准', () {
      final base = ProgressEntryState(
        bookId: 'b1',
        page: 3,
        completed: false,
        updatedAt: t0,
        serverLastModified: t0,
      );
      final next = ProgressOutboxRules.applyEnqueue(
        target: target('b1', 8),
        current: base,
        seq: 42,
        now: t1,
      );
      expect(next.page, 8);
      expect(next.pendingSeq, 42);
      expect(next.serverLastModified, t0);
    });

    test('planAdoptRemote 非强制有 pending 保留本地，强制模式覆盖并清空 pending', () {
      final pending = ProgressEntryState(
        bookId: 'b1',
        page: 10,
        completed: false,
        updatedAt: t0,
        pendingSeq: 99,
      );
      final remote = ReadProgress(page: 4, completed: true, lastModified: t1);

      final guarded = ProgressOutboxRules.planAdoptRemote(
        bookId: 'b1',
        current: pending,
        remote: remote,
        now: t1,
      );
      expect(guarded.action, ProgressAdoptAction.keepLocal);

      final forced = ProgressOutboxRules.planAdoptRemote(
        bookId: 'b1',
        current: pending,
        remote: remote,
        now: t1,
        force: true,
      );
      expect(forced.action, ProgressAdoptAction.upsert);
      expect(forced.entry!.page, 4);
      expect(forced.entry!.completed, isTrue);
      expect(forced.entry!.pendingSeq, isNull);
    });
  });

  group('decideSync', () {
    final t0 = DateTime.utc(2026, 11, 17, 10);
    final t1 = t0.add(const Duration(minutes: 5));
    final t2 = t0.add(const Duration(minutes: 10));

    test('本地有待提交 → 先推本地（后写者胜）', () {
      final decision = decideSync(
        base: ReadProgress(page: 3, completed: false, lastModified: t0),
        remote: ReadProgress(page: 9, completed: false, lastModified: t2),
        hasPending: true,
      );
      expect(decision.action, SyncAction.pushLocal);
    });

    test('本地首次见到 → 采纳服务端', () {
      final decision = decideSync(
        base: null,
        remote: ReadProgress(page: 3, completed: false, lastModified: t0),
        hasPending: false,
      );
      expect(decision.action, SyncAction.adoptRemote);
      expect(decision.remote!.page, 3);
    });

    test('双方无进度 → 无动作', () {
      expect(
        decideSync(base: null, remote: null, hasPending: false).action,
        SyncAction.inSync,
      );
    });

    test('服务端进度被删除 → 采纳为空（回到未读）', () {
      final decision = decideSync(
        base: ReadProgress(page: 3, completed: false, lastModified: t0),
        remote: null,
        hasPending: false,
      );
      expect(decision.action, SyncAction.adoptRemote);
      expect(decision.remote, isNull);
    });

    test('其他设备读得更远 → 采纳并说明原因', () {
      final decision = decideSync(
        base: ReadProgress(page: 3, completed: false, lastModified: t0),
        remote: ReadProgress(page: 12, completed: false, lastModified: t1),
        hasPending: false,
      );
      expect(decision.action, SyncAction.adoptRemote);
      expect(decision.remote!.page, 12);
      expect(decision.reason, contains('更远'));
    });

    test('服务端时间不新于基准 → 视为旧快照，不覆盖本地', () {
      final decision = decideSync(
        base: ReadProgress(page: 12, completed: false, lastModified: t1),
        remote: ReadProgress(page: 4, completed: false, lastModified: t0),
        hasPending: false,
      );
      expect(decision.action, SyncAction.staleRemote);
    });

    test('服务端完成态被标记 → 采纳完成，但不改页码', () {
      final decision = decideSync(
        base: ReadProgress(page: 20, completed: false, lastModified: t0),
        remote: ReadProgress(page: 20, completed: true, lastModified: t1),
        hasPending: false,
      );
      expect(decision.action, SyncAction.adoptRemote);
      expect(decision.remote!.completed, isTrue);
      expect(decision.remote!.page, 20);
    });
  });
}
