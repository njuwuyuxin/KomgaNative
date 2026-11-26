import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart' show kLocalSourceKey;
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';
import 'support/test_source_overrides.dart';

/// RDR-06：双页"从这一页起分组"按书记住，退出重进仍在，且可以恢复自动。
void main() {
  group('ReaderPrefs.spreadFrom', () {
    test('按书写入 / 覆盖 / 清除', () {
      var prefs = const ReaderPrefs().withSpreadFrom('b1', 2);
      expect(prefs.spreadFrom['b1'], 2);
      // 换书不串。
      expect(prefs.spreadFrom['b2'], isNull);

      prefs = prefs.withSpreadFrom('b1', 4);
      expect(prefs.spreadFrom['b1'], 4);

      prefs = prefs.withSpreadFrom('b1', null);
      expect(prefs.spreadFrom, isEmpty);

      // 负数当"恢复自动"处理，不留脏数据。
      expect(const ReaderPrefs().withSpreadFrom('b1', -1).spreadFrom, isEmpty);
    });

    test('存档往返：合法条目保留，坏条目丢弃', () {
      final prefs = const ReaderPrefs()
          .withSpreadFrom('b1', 2)
          .withSpreadFrom('b2', 0);
      expect(ReaderPrefs.fromJson(prefs.toJson()).spreadFrom, prefs.spreadFrom);

      // 手工改坏的存档：非 Map / 非 int / 负数 / 空 key 都要扛住。
      final broken = ReaderPrefs.fromJson(const <String, Object?>{
        'spreadFrom': <String, Object?>{
          'ok': 3,
          'bad-type': '2',
          'negative': -1,
          '': 5,
          'null-value': null,
        },
      });
      expect(broken.spreadFrom, <String, int>{'ok': 3});

      final notMap = ReaderPrefs.fromJson(const <String, Object?>{
        'spreadFrom': 'nope',
      });
      expect(notMap.spreadFrom, isEmpty);
    });

    test('不进预设快照：ReaderConfig 天然不含 spreadFrom', () {
      final prefs = const ReaderPrefs().withSpreadFrom('b1', 2);
      expect(prefs.global.toJson().containsKey('spreadFrom'), isFalse);
    });

    test('系列覆盖不影响按书的分组', () {
      final prefs = const ReaderPrefs()
          .withSpreadFrom('b1', 2)
          .withSeriesOverride(
            's1',
            const ReaderConfig(mode: ReaderModeChoice.single),
          );
      expect(prefs.spreadFrom['b1'], 2);
      expect(prefs.forSeries('s1').mode, ReaderModeChoice.single);
    });
  });

  group('阅读器里的分组持久化', () {
    test('控制器写入后能从存档读回', () async {
      final store = InMemoryReaderPrefsStore();
      final container = ProviderContainer(
        overrides: <Override>[
          readerPrefsStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      container.read(readerPrefsProvider);
      await Future<void>.delayed(Duration.zero);

      container
          .read(readerPrefsProvider.notifier)
          .setSpreadFrom('b1', 2, serverKey: kLocalSourceKey);
      await Future<void>.delayed(Duration.zero);

      expect(store.prefs?.spreadFrom['b1'], 2);
      expect(container.read(readerPrefsProvider).spreadFrom['b1'], 2);
    });

    testWidgets('长按缩略图设定分组 → 落盘，重进仍然是这个分组', (WidgetTester tester) async {
      final store = await pumpReader(
        tester,
        repository: FakeReaderRepository(pageCount: 6),
        book: demoReaderBook(),
        initialPrefs: const ReaderPrefs(
          global: ReaderConfig(mode: ReaderModeChoice.double),
        ),
      );

      // 先跳到第 3 页（默认它在 [1,2] 这一屏里）。
      await openPages(tester);
      await tester.tap(find.byKey(const Key('page-thumb-3')));
      await tester.pumpAndSettle();

      // 长按第 3 页缩略图：从这一页重新分组。
      await openPages(tester);
      expect(
        find.byKey(const Key('page-navigator-grid')),
        findsOneWidget,
        reason: '缩略图面板要真的打开',
      );
      await tester.longPress(find.byKey(const Key('page-thumb-3')));
      await tester.pumpAndSettle();

      expect(
        store.prefs?.spreadFromFor('b1', serverKey: kTestKomgaSourceKey),
        2,
        reason: '0 基的第 3 页 = index 2',
      );
      final view = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
      expect(view.spread, <int>[2, 3]);

      // 模拟"退出再进"：用同一份存档重新建阅读器。
      await pumpReader(
        tester,
        repository: FakeReaderRepository(pageCount: 6),
        book: demoReaderBook(),
        initialPrefs: store.prefs,
      );
      await tester.pumpAndSettle();

      final reopened = tester.widget<ReaderPagedView>(
        find.byType(ReaderPagedView),
      );
      expect(reopened.spread, <int>[2, 3], reason: '重进保持手动分组');
    });
  });
}
