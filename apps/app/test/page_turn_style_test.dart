import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// RDR-05：翻页动画可选（卷页/平移/淡入/瞬切），e-ink 与减少动态效果强制瞬切。
void main() {
  const base = Duration(milliseconds: 450);

  PageTurnStyle resolve(
    ReaderPageTurnChoice choice, {
    bool eink = false,
    bool disableAnimations = false,
    Duration duration = base,
  }) => PageTurnStyle.resolve(
    choice: choice,
    eink: eink,
    disableAnimations: disableAnimations,
    duration: duration,
  );

  group('PageTurnStyle.resolve', () {
    test('四个档位映射到对应效果', () {
      expect(resolve(ReaderPageTurnChoice.curl).effect, PageTurnEffect.curl);
      expect(resolve(ReaderPageTurnChoice.slide).effect, PageTurnEffect.slide);
      expect(resolve(ReaderPageTurnChoice.fade).effect, PageTurnEffect.fade);
      expect(resolve(ReaderPageTurnChoice.none).effect, PageTurnEffect.none);
    });

    test('墨水屏一律瞬切（哪怕用户选了卷页）', () {
      expect(
        resolve(ReaderPageTurnChoice.curl, eink: true).effect,
        PageTurnEffect.none,
      );
    });

    test('系统"减少动态效果"一律瞬切', () {
      expect(
        resolve(ReaderPageTurnChoice.curl, disableAnimations: true).effect,
        PageTurnEffect.none,
      );
    });

    test('时长被 token 压成 0 时也瞬切', () {
      expect(
        resolve(ReaderPageTurnChoice.slide, duration: Duration.zero).effect,
        PageTurnEffect.none,
      );
    });

    test('时长来自传入的 token，不再是写死的 400ms', () {
      expect(resolve(ReaderPageTurnChoice.curl).duration, base);
    });
  });

  test('控制器会从存档恢复翻页动画', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        readerPrefsStoreProvider.overrideWithValue(
          InMemoryReaderPrefsStore(
            const ReaderPrefs(
              global: ReaderConfig(pageTurn: ReaderPageTurnChoice.fade),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(readerPrefsProvider);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      container.read(readerPrefsProvider).global.pageTurn,
      ReaderPageTurnChoice.fade,
    );
  });

  test('setPageTurn 会落盘', () async {
    final store = InMemoryReaderPrefsStore();
    final container = ProviderContainer(
      overrides: <Override>[readerPrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.read(readerPrefsProvider);
    await Future<void>.delayed(Duration.zero);

    container
        .read(readerPrefsProvider.notifier)
        .setPageTurn(ReaderPageTurnChoice.fade);
    await Future<void>.delayed(Duration.zero);

    expect(store.prefs?.global.pageTurn, ReaderPageTurnChoice.fade);
    expect(
      container.read(readerPrefsProvider).global.pageTurn,
      ReaderPageTurnChoice.fade,
    );
  });

  testWidgets('设置里的选择会传到绘制层', (WidgetTester tester) async {
    final store = await pumpReader(
      tester,
      book: demoReaderBook(),
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(pageTurn: ReaderPageTurnChoice.fade),
      ),
    );

    expect(
      store.prefs?.global.pageTurn,
      ReaderPageTurnChoice.fade,
      reason: '存档里是 fade',
    );
    expect(find.byType(ReaderPagedView), findsOneWidget);

    final view = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
    expect(view.style.effect, PageTurnEffect.fade);
    expect(view.style.animates, isTrue);
  });

  testWidgets('墨水屏即使选了卷页也走瞬切', (WidgetTester tester) async {
    await pumpReader(
      tester,
      book: demoReaderBook(),
      forceEink: true,
      initialPrefs: const ReaderPrefs(
        global: ReaderConfig(pageTurn: ReaderPageTurnChoice.curl),
      ),
    );

    final view = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
    expect(view.style.effect, PageTurnEffect.none);
    expect(view.style.animates, isFalse);
  });
}
