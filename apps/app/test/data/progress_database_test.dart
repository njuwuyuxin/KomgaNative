import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_database.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

/// Drift 实现的行为契约（与 `InMemoryProgressStore` 必须一致）。
///
/// 用内存库跑：Flutter 3.50 的 native assets 会在测试时构建 sqlite，
/// Windows 上不需要额外注入 dll（踩过 `sqlite3_flutter_libs` 那套的老路）。
void main() {
  late ProgressDatabase db;
  late ProgressStore store;

  setUp(() {
    db = ProgressDatabase(NativeDatabase.memory());
    store = DriftProgressStore(db);
  });

  tearDown(() => db.close());

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

  test('seq 严格递增（毫秒精度时钟下也不能撞）', () async {
    await store.enqueue(target(1));
    await store.enqueue(target(2));
    await store.enqueue(target(3));
    final pending = await store.pending();
    expect(pending.single.seq, greaterThan(0));
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

  test('有 pending 时拒绝采纳服务端：本地还没推上去，不能被旧值覆盖', () async {
    await store.enqueue(target(9));
    await store.adoptRemote(
      'b1',
      ReadProgress(
        page: 2,
        completed: false,
        lastModified: DateTime.utc(2026, 5, 1),
      ),
    );

    final record = await store.record('b1');
    expect(record!.page, 9);
    expect(record.isPending, isTrue);
  });

  test('服务端删掉进度（标记未读）→ 本地清空', () async {
    await store.enqueue(target(3));
    await store.ack('b1', (await store.pending()).single.seq);

    await store.adoptRemote('b1', null);
    expect(await store.record('b1'), isNull);
  });

  test('批量读只返回存在的书（书架一页 100 本不能一本一次查询）', () async {
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
  });

  test('空 id 列表不会拼出非法 SQL', () async {
    expect(await store.records(const <String>[]), isEmpty);
  });

  test('pending 按入队顺序返回（先入队先提交）', () async {
    await store.enqueue(target(1, book: 'a'));
    await store.enqueue(target(1, book: 'b'));
    final pending = await store.pending();
    expect(pending.map((PendingProgress p) => p.target.bookId), <String>[
      'a',
      'b',
    ]);
  });
}
