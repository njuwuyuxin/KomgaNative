import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';

/// FIX-04：预设是"完整快照"。应用时漏抄一个字段，用户会看到
/// "套了预设但锁定缩放/去白边没生效"——而且只有一部分人开着这两项，很难被报上来。
void main() {
  Future<ProviderContainer> containerWith(ReaderPrefs? initial) async {
    final container = ProviderContainer(
      overrides: <Override>[
        readerPrefsStoreProvider.overrideWithValue(
          InMemoryReaderPrefsStore(initial),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(readerPrefsProvider);
    // 让 build() 里的异步恢复落地。
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container;
  }

  /// 一份"每个字段都不是默认值"的配置，漏抄任何一个都会被测出来。
  const full = ReaderPrefs(
    mode: ReaderModeChoice.double,
    brightness: 0.5,
    keepAwake: true,
    fit: ReaderFitChoice.cover,
    direction: ReaderDirectionChoice.rightToLeft,
    background: ReaderBackgroundChoice.white,
    lockZoom: true,
    trimBorders: true,
  );

  String savePresetAndGetId(ProviderContainer container, {String? seriesId}) {
    final controller = container.read(readerPrefsProvider.notifier);
    controller.savePreset('我的预设', seriesId: seriesId);
    return container.read(readerPrefsProvider).presets.last.id;
  }

  test('全局应用预设：逐字段覆盖，锁定缩放/去白边不丢', () async {
    final container = await containerWith(full);
    final id = savePresetAndGetId(container);
    final controller = container.read(readerPrefsProvider.notifier);

    // 全部改回相反值。
    controller
      ..setMode(ReaderModeChoice.single)
      ..setBrightness(1)
      ..setKeepAwake(false)
      ..setFit(ReaderFitChoice.contain)
      ..setDirection(ReaderDirectionChoice.leftToRight)
      ..setBackground(ReaderBackgroundChoice.black)
      ..setLockZoom(false)
      ..setTrimBorders(false);

    controller.applyPreset(id);

    final applied = container.read(readerPrefsProvider);
    expect(applied.configOnly(), full, reason: '应用后必须与保存时的快照完全一致');
    // 预设列表本身不能被应用动作改掉。
    expect(applied.presets, hasLength(1));
  });

  test('按系列应用预设：同样完整，且不影响全局', () async {
    final container = await containerWith(full);
    final id = savePresetAndGetId(container);
    final controller = container.read(readerPrefsProvider.notifier);

    controller.applyPreset(id, seriesId: 's1');

    final state = container.read(readerPrefsProvider);
    expect(state.forSeries('s1').configOnly(), full);
    // 全局保持原样（这里全局本来就是 full，所以要显式验证覆盖确实写进去了）。
    expect(state.seriesOverrides['s1']?.configOnly(), full);
  });

  test('删掉系列覆盖后回到全局；全局也完整', () async {
    // 全局用一份和预设不同的配置，才能看出"回全局"到底回到了什么。
    final container = await containerWith(
      const ReaderPrefs(mode: ReaderModeChoice.vertical),
    );
    final controller = container.read(readerPrefsProvider.notifier);
    // 先在系列里做出 full，并保存成预设。
    controller
      ..setMode(ReaderModeChoice.double, seriesId: 's1')
      ..setLockZoom(true, seriesId: 's1')
      ..setTrimBorders(true, seriesId: 's1');
    final id = savePresetAndGetId(container, seriesId: 's1');

    controller
      ..setLockZoom(false, seriesId: 's1')
      ..setTrimBorders(false, seriesId: 's1')
      ..applyPreset(id, seriesId: 's1');

    var state = container.read(readerPrefsProvider);
    expect(state.forSeries('s1').lockZoom, isTrue);
    expect(state.forSeries('s1').trimBorders, isTrue);
    expect(state.forSeries('s1').mode, ReaderModeChoice.double);

    controller.setSeriesOverride('s1', false);

    state = container.read(readerPrefsProvider);
    expect(state.seriesOverrides, isEmpty);
    // 回全局：全局是 vertical、没开锁定缩放/去白边。
    expect(state.forSeries('s1').mode, ReaderModeChoice.vertical);
    expect(state.forSeries('s1').lockZoom, isFalse);
    expect(state.forSeries('s1').trimBorders, isFalse);
  });

  test('旧存档的预设没有锁定缩放/去白边字段：按 false 应用，不崩', () async {
    // 模拟"预设是在这两个开关出现之前存的"。
    final legacy = ReaderPrefs.fromJson(const <String, Object?>{
      'presets': <Object?>[
        <String, Object?>{
          'id': 'old-1',
          'name': '旧预设',
          'prefs': <String, Object?>{'mode': 'single'},
        },
      ],
    });
    final container = await containerWith(legacy);
    final controller = container.read(readerPrefsProvider.notifier);

    controller
      ..setLockZoom(true)
      ..setTrimBorders(true)
      ..applyPreset('old-1');

    final applied = container.read(readerPrefsProvider);
    expect(applied.mode, ReaderModeChoice.single);
    expect(applied.lockZoom, isFalse);
    expect(applied.trimBorders, isFalse);
  });

  test('应用不存在的预设 id：什么也不改', () async {
    final container = await containerWith(full);
    final before = container.read(readerPrefsProvider);

    container.read(readerPrefsProvider.notifier).applyPreset('missing');

    expect(container.read(readerPrefsProvider), before);
  });
}
