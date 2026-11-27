import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

/// 生产 [DriftProgressStore] 与测试 [InMemoryProgressStore] 的共享契约测试（P2-3）。
///
/// 两者共用 `packages/yomu_sync` 的 [ProgressOutboxRules]，本套用例对两种实现执行
/// 完全相同的断言矩阵，保证测试语义与线上 SQLite 持久化行为零漂移。
void _runProgressStoreContract(
  String label,
  Future<({ProgressStore store, Future<void> Function() dispose})> Function()
  createStore,
) {
  group('$label（共享 ProgressOutboxRules 契约）', () {
    late ProgressStore store;
    late Future<void> Function() disposeStore;

    setUp(() async {
      final handle = await createStore();
      store = handle.store;
      disposeStore = handle.dispose;
    });

    tearDown(() => disposeStore());

    ProgressTarget target(
      int page, {
      bool completed = false,
      String book = 'b1',
    }) => ProgressTarget(bookId: book, page: page, completed: completed);

    test('同一本书重复入队只保留最新一条（翻页不能堆成队列）', () async {
      await store.enqueue(target(1));
      await store.enqueue(target(2));
      await store.enqueue(target(3));

      final pending = await store.pending();
      expect(pending, hasLength(1));
      expect(pending.single.target.page, 3);

      final record = await store.record('b1');
      expect(record!.page, 3);
      expect(record.isPending, isTrue);
    });

    test('seq 严格递增且再次入队保留 serverLastModified 基准', () async {
      final remoteTime = DateTime.utc(2026, 5, 1, 12);
      await store.adoptRemote(
        'b1',
        ReadProgress(page: 2, completed: false, lastModified: remoteTime),
      );
      await store.enqueue(target(3));
      final seq1 = (await store.pending()).single.seq;
      await store.enqueue(target(4));
      final seq2 = (await store.pending()).single.seq;

      expect(seq2, greaterThan(seq1));
      final rec = await store.record('b1');
      expect(rec!.serverLastModified, remoteTime);
    });

    test('提交成功的回执清空 pending，并把服务端基准置空', () async {
      await store.enqueue(target(2));
      final seq = (await store.pending()).single.seq;

      expect(await store.ack('b1', seq), isTrue);
      final record = await store.record('b1');
      expect(record!.isPending, isFalse);
      expect(record.page, 2, reason: '本地已知进度要保留');
      expect(record.serverLastModified, isNull, reason: 'PATCH 无响应体，基准未知');
      expect(await store.pending(), isEmpty);
    });

    test('回执 seq 不匹配（提交期间又翻页）→ 不能删掉新进度', () async {
      await store.enqueue(target(2));
      final stale = (await store.pending()).single.seq;
      await store.enqueue(target(5));

      expect(await store.ack('b1', stale), isFalse);

      final pending = await store.pending();
      expect(pending.single.target.page, 5, reason: '新进度必须还在队列里');
    });

    test('采纳服务端进度：没有 pending 时写入，并记下服务端时间', () async {
      final remote = ReadProgress(
        page: 7,
        completed: false,
        lastModified: DateTime.utc(2026, 5, 1, 12),
      );
      await store.adoptRemote('b1', remote);

      final record = await store.record('b1');
      expect(record!.page, 7);
      expect(record.isPending, isFalse);
      expect(record.serverLastModified, DateTime.utc(2026, 5, 1, 12));
    });

    test('有 pending 时拒绝采纳服务端；forceAdopt 强制覆盖并清掉 pending', () async {
      await store.enqueue(target(9));
      final remote = ReadProgress(
        page: 2,
        completed: false,
        lastModified: DateTime.utc(2026, 5, 1),
      );
      await store.adoptRemote('b1', remote);

      var record = await store.record('b1');
      expect(record!.page, 9);
      expect(record.isPending, isTrue);

      await store.forceAdopt('b1', remote);
      record = await store.record('b1');
      expect(record!.page, 2);
      expect(record.isPending, isFalse);
      expect(await store.pending(), isEmpty);
    });

    test('服务端删掉进度（标记未读）→ 本地清空', () async {
      await store.enqueue(target(3));
      await store.ack('b1', (await store.pending()).single.seq);

      await store.adoptRemote('b1', null);
      expect(await store.record('b1'), isNull);
    });

    test('批量读只返回存在的书且空 id 列表安全返回空表', () async {
      await store.adoptRemote(
        'b1',
        ReadProgress(
          page: 1,
          completed: true,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      );
      await store.adoptRemote(
        'b2',
        ReadProgress(
          page: 4,
          completed: false,
          lastModified: DateTime.utc(2026, 1, 2),
        ),
      );

      final records = await store.records(<String>['b1', 'b2', 'missing']);
      expect(records.keys, containsAll(<String>['b1', 'b2']));
      expect(records['b1']!.completed, isTrue);
      expect(records['b2']!.page, 4);
      expect(records.containsKey('missing'), isFalse);
      expect(await store.records(const <String>[]), isEmpty);
    });

    test('pending 按最新入队顺序返回（重入队的书排到队尾）', () async {
      await store.enqueue(target(1, book: 'a'));
      await store.enqueue(target(1, book: 'b'));
      await store.enqueue(target(2, book: 'a'));
      final pending = await store.pending();
      expect(pending.map((PendingProgress p) => p.target.bookId), <String>[
        'b',
        'a',
      ]);
      expect(pending.last.target.page, 2);
    });

    test('多 scope 物理隔离且 clearScope 只清理指定服务器分区', () async {
      const serverA = 'https://a.example';
      const serverB = 'https://b.example';
      await store.enqueue(target(3, book: 'same'), scope: serverA);
      await store.enqueue(target(9, book: 'same'), scope: serverB);

      expect((await store.record('same', scope: serverA))?.page, 3);
      expect((await store.record('same', scope: serverB))?.page, 9);

      await store.clearScope(serverA);
      expect(await store.record('same', scope: serverA), isNull);
      expect(await store.pending(scope: serverA), isEmpty);
      expect((await store.record('same', scope: serverB))?.page, 9);
      expect(await store.pending(scope: serverB), hasLength(1));
    });
  });
}

void main() {
  _runProgressStoreContract('DriftProgressStore', () async {
    final db = ProgressDatabase(NativeDatabase.memory());
    return (store: DriftProgressStore(db), dispose: db.close);
  });

  _runProgressStoreContract('InMemoryProgressStore', () async {
    return (store: InMemoryProgressStore(), dispose: () async {});
  });
}
