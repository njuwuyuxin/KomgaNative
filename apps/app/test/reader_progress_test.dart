import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 阅读器与 outbox 的接缝：翻页必须先落本地，服务端能不能收到是第二件事。
void main() {
  testWidgets('断网翻页：进度先落本地，联网后补交', (WidgetTester tester) async {
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository(
      saveFailure: const NetworkFailure(),
    );
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      progressStore: progressStore,
    );

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));

    // 服务端没收到，但本地队列里有第 2 页。
    expect(repository.saved, isEmpty, reason: '断网时上传必然失败');
    final pending = await progressStore.pending();
    expect(pending, hasLength(1));
    expect(pending.single.target.page, 2);

    // 网络恢复：下一次翻页会顺带把积压的进度一起推上去。
    repository.saveFailure = null;
    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(await progressStore.pending(), isEmpty);
    // 同书只保留最新一条：补交的是第 3 页，而不是先补 2 再补 3。
    expect(
      repository.saved.map((({int page, bool completed}) s) => s.page),
      <int>[3],
    );
  });

  testWidgets('进度已落本地：即使上传失败，页码也不会回退', (WidgetTester tester) async {
    final progressStore = InMemoryProgressStore();
    final repository = FakeReaderRepository(
      saveFailure: const NetworkFailure(),
    );
    await pumpReader(
      tester,
      repository: repository,
      book: demoReaderBook(),
      progressStore: progressStore,
    );

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('2 / 3'), findsOneWidget);

    // 本地记录已经是第 2 页，重建阅读器（模拟返回列表再进来）应停在这里。
    final record = await progressStore.record('b1');
    expect(record!.page, 2);
  });
}
