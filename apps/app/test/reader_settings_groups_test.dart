import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart' show kLocalSourceKey;
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';

/// RDR-04：四组设置各自可重置，且只影响自己那一组。
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

  /// 每个字段都不是默认值。
  const allChanged = ReaderPrefs(
    global: ReaderConfig(
      mode: ReaderModeChoice.double,
      brightness: 0.5,
      keepAwake: true,
      fit: ReaderFitChoice.cover,
      direction: ReaderDirectionChoice.rightToLeft,
      background: ReaderBackgroundChoice.white,
      lockZoom: true,
      trimBorders: true,
      pageTurn: ReaderPageTurnChoice.fade,
    ),
  );

  test('「页面」组只重置模式，其它组不动', () async {
    final container = await containerWith(allChanged);
    container
        .read(readerPrefsProvider.notifier)
        .resetGroup(ReaderSettingsGroup.pages);

    final prefs = container.read(readerPrefsProvider).global;
    expect(prefs.mode, ReaderModeChoice.auto);
    expect(prefs.fit, ReaderFitChoice.cover);
    expect(prefs.direction, ReaderDirectionChoice.rightToLeft);
    expect(prefs.background, ReaderBackgroundChoice.white);
    expect(prefs.brightness, 0.5);
    expect(prefs.lockZoom, isTrue);
    expect(prefs.keepAwake, isTrue);
    expect(prefs.trimBorders, isTrue);
  });

  test('「布局」组重置适配 / 方向 / 去白边', () async {
    final container = await containerWith(allChanged);
    container
        .read(readerPrefsProvider.notifier)
        .resetGroup(ReaderSettingsGroup.layout);

    final prefs = container.read(readerPrefsProvider).global;
    expect(prefs.fit, ReaderFitChoice.contain);
    expect(prefs.direction, ReaderDirectionChoice.auto);
    expect(prefs.trimBorders, isFalse);
    // 其它组不受影响。
    expect(prefs.mode, ReaderModeChoice.double);
    expect(prefs.background, ReaderBackgroundChoice.white);
    expect(prefs.brightness, 0.5);
    expect(prefs.lockZoom, isTrue);
  });

  test('「颜色」组重置背景 / 亮度', () async {
    final container = await containerWith(allChanged);
    container
        .read(readerPrefsProvider.notifier)
        .resetGroup(ReaderSettingsGroup.color);

    final prefs = container.read(readerPrefsProvider).global;
    expect(prefs.background, ReaderBackgroundChoice.black);
    expect(prefs.brightness, 1);
    expect(prefs.mode, ReaderModeChoice.double);
    expect(prefs.fit, ReaderFitChoice.cover);
  });

  test('「交互」组重置锁定缩放 / 常亮', () async {
    final container = await containerWith(allChanged);
    container
        .read(readerPrefsProvider.notifier)
        .resetGroup(ReaderSettingsGroup.interaction);

    final prefs = container.read(readerPrefsProvider).global;
    expect(prefs.lockZoom, isFalse);
    expect(prefs.keepAwake, isFalse);
    expect(prefs.pageTurn, ReaderPageTurnChoice.curl);
    expect(prefs.mode, ReaderModeChoice.double);
    expect(prefs.trimBorders, isTrue);
  });

  test('isGroupDefault 判断与 reset 一致', () async {
    final container = await containerWith(allChanged);
    final controller = container.read(readerPrefsProvider.notifier);

    // 全改了：四组都不是默认。
    for (final group in ReaderSettingsGroup.values) {
      expect(
        container.read(readerPrefsProvider).global.isGroupDefault(group),
        isFalse,
        reason: '$group 应该是"已改过"',
      );
      controller.resetGroup(group);
      expect(
        container.read(readerPrefsProvider).global.isGroupDefault(group),
        isTrue,
        reason: '$group 重置后应该算默认',
      );
    }
  });

  test('系列覆盖的重置只影响那个系列', () async {
    final container = await containerWith(allChanged);
    final controller = container.read(readerPrefsProvider.notifier);
    controller.setSeriesOverride('s1', true, serverKey: kLocalSourceKey);
    controller.setFit(
      ReaderFitChoice.fitWidth,
      seriesId: 's1',
      serverKey: kLocalSourceKey,
    );

    controller.resetGroup(
      ReaderSettingsGroup.layout,
      seriesId: 's1',
      serverKey: kLocalSourceKey,
    );

    final prefs = container.read(readerPrefsProvider);
    expect(prefs.forSeries('s1').fit, ReaderFitChoice.contain);
    // 全局的 fit 仍是原来那个。
    expect(prefs.global.fit, ReaderFitChoice.cover);
  });
}
