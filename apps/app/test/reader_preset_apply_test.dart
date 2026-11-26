import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu_reader/yomu_reader.dart' show TapZonePreset;

/// FIX-04 & ARC-04：`ReaderConfig` 值对象全字段往返、预设应用与系列覆盖不漂移。
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
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container;
  }

  /// 一份"全部 14 个 ReaderConfig 字段都不是默认值"的配置。
  const fullConfig = ReaderConfig(
    mode: ReaderModeChoice.double,
    brightness: 0.45,
    keepAwake: true,
    fit: ReaderFitChoice.cover,
    direction: ReaderDirectionChoice.rightToLeft,
    background: ReaderBackgroundChoice.immersive,
    lockZoom: true,
    trimBorders: true,
    pageTurn: ReaderPageTurnChoice.fade,
    tapZone: TapZonePreset.kindle,
    invertTapZones: true,
    doubleTapZoom: false,
    autoScrollSpeed: 8,
    showSessionTime: false,
  );

  const fullPrefs = ReaderPrefs(global: fullConfig);

  String savePresetAndGetId(ProviderContainer container, {String? seriesId}) {
    final controller = container.read(readerPrefsProvider.notifier);
    controller.savePreset('我的预设', seriesId: seriesId);
    return container.read(readerPrefsProvider).presets.last.id;
  }

  test('全部 14 个非默认字段：保存为预设 → 应用到全局 → 逐字段与 hashCode 全等', () async {
    final container = await containerWith(fullPrefs);
    final id = savePresetAndGetId(container);
    final controller = container.read(readerPrefsProvider.notifier);

    // 全部改回相反/默认值。
    controller
      ..setMode(ReaderModeChoice.single)
      ..setBrightness(1)
      ..setKeepAwake(false)
      ..setFit(ReaderFitChoice.contain)
      ..setDirection(ReaderDirectionChoice.leftToRight)
      ..setBackground(ReaderBackgroundChoice.black)
      ..setLockZoom(false)
      ..setTrimBorders(false)
      ..setPageTurn(ReaderPageTurnChoice.curl)
      ..setTapZone(TapZonePreset.automatic)
      ..setInvertTapZones(false)
      ..setDoubleTapZoom(true)
      ..setAutoScrollSpeed(5)
      ..setShowSessionTime(true);

    controller.applyPreset(id);

    final applied = container.read(readerPrefsProvider);
    expect(applied.global, fullConfig, reason: '14 个字段含 pageTurn 等必须一字不漏还原');
    expect(applied.global.hashCode, fullConfig.hashCode);
    expect(applied.presets, hasLength(1));
  });

  test('全部 14 个非默认字段：应用到系列覆盖 → forSeries 全等，且不影响全局', () async {
    final container = await containerWith(const ReaderPrefs());
    final controller = container.read(readerPrefsProvider.notifier);

    // 在系列 s1 上构造全非默认配置并存成预设。
    controller
      ..setSeriesOverride('s1', true)
      ..setMode(fullConfig.mode, seriesId: 's1')
      ..setBrightness(fullConfig.brightness, seriesId: 's1')
      ..setKeepAwake(fullConfig.keepAwake, seriesId: 's1')
      ..setFit(fullConfig.fit, seriesId: 's1')
      ..setDirection(fullConfig.direction, seriesId: 's1')
      ..setBackground(fullConfig.background, seriesId: 's1')
      ..setLockZoom(fullConfig.lockZoom, seriesId: 's1')
      ..setTrimBorders(fullConfig.trimBorders, seriesId: 's1')
      ..setPageTurn(fullConfig.pageTurn, seriesId: 's1')
      ..setTapZone(fullConfig.tapZone, seriesId: 's1')
      ..setInvertTapZones(fullConfig.invertTapZones, seriesId: 's1')
      ..setDoubleTapZoom(fullConfig.doubleTapZoom, seriesId: 's1')
      ..setAutoScrollSpeed(fullConfig.autoScrollSpeed, seriesId: 's1')
      ..setShowSessionTime(fullConfig.showSessionTime, seriesId: 's1');

    final id = savePresetAndGetId(container, seriesId: 's1');
    controller.applyPreset(id, seriesId: 's2');

    final state = container.read(readerPrefsProvider);
    expect(state.forSeries('s1'), fullConfig);
    expect(state.forSeries('s2'), fullConfig);
    expect(state.seriesOverrides['s2'], fullConfig);
    expect(state.global, const ReaderConfig(), reason: '全局保持默认值不变');
  });

  test('删掉系列覆盖后回到全局；全局也完整', () async {
    final container = await containerWith(
      const ReaderPrefs(global: ReaderConfig(mode: ReaderModeChoice.vertical)),
    );
    final controller = container.read(readerPrefsProvider.notifier);
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
    expect(state.forSeries('s1').mode, ReaderModeChoice.vertical);
    expect(state.forSeries('s1').lockZoom, isFalse);
    expect(state.forSeries('s1').trimBorders, isFalse);
  });

  test('旧存档扁平 JSON 与旧预设反序列化兼容', () async {
    final legacy = ReaderPrefs.fromJson(const <String, Object?>{
      'mode': 'double',
      'pageTurn': 'slide',
      'tabletLayout': 'single',
      'presets': <Object?>[
        <String, Object?>{
          'id': 'old-1',
          'name': '旧预设',
          'prefs': <String, Object?>{'mode': 'single'},
        },
      ],
    });
    expect(legacy.global.mode, ReaderModeChoice.double);
    expect(legacy.global.pageTurn, ReaderPageTurnChoice.slide);
    expect(legacy.tabletLayout, TabletLayoutChoice.single);

    final container = await containerWith(legacy);
    final controller = container.read(readerPrefsProvider.notifier);

    controller
      ..setLockZoom(true)
      ..setTrimBorders(true)
      ..applyPreset('old-1');

    final applied = container.read(readerPrefsProvider);
    expect(applied.global.mode, ReaderModeChoice.single);
    expect(applied.global.lockZoom, isFalse);
    expect(applied.global.trimBorders, isFalse);
  });

  test('hashCode 覆盖 showSessionTime / autoScrollSpeed / tabletLayout 变更', () {
    const base = ReaderPrefs();
    expect(
      base.copyWith(global: base.global.copyWith(showSessionTime: false)),
      isNot(equals(base)),
    );
    expect(
      base
          .copyWith(global: base.global.copyWith(showSessionTime: false))
          .hashCode,
      isNot(equals(base.hashCode)),
    );
    expect(
      base.copyWith(global: base.global.copyWith(autoScrollSpeed: 9)).hashCode,
      isNot(equals(base.hashCode)),
    );
    expect(
      base.copyWith(tabletLayout: TabletLayoutChoice.double).hashCode,
      isNot(equals(base.hashCode)),
    );
  });

  test('应用不存在的预设 id：什么也不改', () async {
    final container = await containerWith(fullPrefs);
    final before = container.read(readerPrefsProvider);

    container.read(readerPrefsProvider.notifier).applyPreset('missing');

    expect(container.read(readerPrefsProvider), before);
  });
}
