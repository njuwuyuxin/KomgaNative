import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

/// 同步服务的规则：先落盘、再提交、失败保留、401 停手、单飞。
void main() {
  late InMemoryProgressStore store;
  late List<ProgressTarget> uploaded;
  late bool networkDown;
  late bool authBroken;

  ProgressSyncService build() => ProgressSyncService(
    store: store,
    upload: (ProgressTarget target) async {
      if (authBroken) throw const AuthFailure();
      if (networkDown) throw const NetworkFailure();
      uploaded.add(target);
    },
  );

  setUp(() {
    store = InMemoryProgressStore();
    uploaded = <ProgressTarget>[];
    networkDown = false;
    authBroken = false;
  });

  Book book(String id, {ReadProgress? progress}) => Book(
    id: id,
    seriesId: 's1',
    name: id,
    pagesCount: 10,
    readProgress: progress,
  );

  ReadProgress remote(int page, DateTime at, {bool completed = false}) =>
      ReadProgress(page: page, completed: completed, lastModified: at);

  group('提交', () {
    test('save 先落盘再提交，成功后队列清空', () async {
      final sync = build();
      await sync.save('b1', page: 3, completed: false);
      await sync.flush();

      expect(uploaded.single.page, 3);
      expect(await store.pending(), isEmpty);
      expect((await store.record('b1'))!.page, 3);
    });

    test('断网：进度留在本地，联网后再 flush 补交', () async {
      networkDown = true;
      final sync = build();
      await sync.save('b1', page: 5, completed: false);
      await sync.flush();

      expect(await store.pending(), hasLength(1), reason: '失败不能丢');
      expect((await store.record('b1'))!.page, 5, reason: '本地已知进度要更新');

      networkDown = false;
      await sync.flush();
      expect(uploaded.single.page, 5);
      expect(await store.pending(), isEmpty);
    });

    test('401 之后本轮停手（不刷服务端日志），重新 save 才恢复', () async {
      authBroken = true;
      final sync = build();
      await sync.save('b1', page: 2, completed: false);
      await sync.save('b2', page: 4, completed: false);
      await sync.flush();

      expect(await store.pending(), hasLength(2), reason: '凭据问题不代表进度错了');
      expect(uploaded, isEmpty);

      // 重新登录后再翻一页 → 恢复提交，并且把之前积压的一起推上去。
      authBroken = false;
      await sync.save('b3', page: 1, completed: false);
      await sync.flush();
      expect((await store.pending()), isEmpty);
    });

    test('单飞：并发 flush 不会把同一条进度提交两次', () async {
      final sync = build();
      await sync.save('b1', page: 2, completed: false);

      await Future.wait(<Future<void>>[
        sync.flush(),
        sync.flush(),
        sync.flush(),
      ]);
      expect(uploaded, hasLength(1));
    });
  });

  group('本地优先叠加', () {
    test('没有本地记录 → 用服务端进度', () async {
      final sync = build();
      final merged = await sync.overlay(<Book>[
        book('b1', progress: remote(3, DateTime.utc(2026, 1, 1))),
      ]);
      expect(merged.single.readProgress!.page, 3);
    });

    test('本地有未提交进度（离线读的）→ 显示本地，不被旧的服务端覆盖', () async {
      final sync = build();
      networkDown = true;
      await sync.save('b1', page: 6, completed: false);

      final merged = await sync.overlay(<Book>[
        book('b1', progress: remote(2, DateTime.utc(2026, 1, 1))),
      ]);
      expect(merged.single.readProgress!.page, 6, reason: '用户刚读到第 6 页');
    });

    test('服务端更新（别的设备读得更远）→ 采纳服务端并写回本地', () async {
      final sync = build();
      // 先建立基准：本地已确认第 2 页
      await store.adoptRemote('b1', remote(2, DateTime.utc(2026, 1, 1)));

      final merged = await sync.overlay(<Book>[
        book('b1', progress: remote(5, DateTime.utc(2026, 1, 2))),
      ]);
      expect(merged.single.readProgress!.page, 5);
      expect((await store.record('b1'))!.page, 5, reason: '写回本地');
    });

    test('服务端时间更旧（乱序响应）→ 不动本地', () async {
      final sync = build();
      await store.adoptRemote('b1', remote(5, DateTime.utc(2026, 1, 5)));

      final merged = await sync.overlay(<Book>[
        book('b1', progress: remote(3, DateTime.utc(2026, 1, 1))),
      ]);
      expect(merged.single.readProgress!.page, 5);
    });

    test('服务端删除进度 → 本地也清空', () async {
      final sync = build();
      await store.adoptRemote('b1', remote(5, DateTime.utc(2026, 1, 5)));

      final merged = await sync.overlay(<Book>[book('b1')]);
      expect(merged.single.readProgress, isNull);
      expect(await store.record('b1'), isNull);
    });

    test('overlayOne 对 null 原样返回（书被删了）', () async {
      final sync = build();
      expect(await sync.overlayOne(null), isNull);
    });
  });
}
