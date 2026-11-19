import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

/// PLT-02：平板默认排版（自动/单页/双页），手机不受影响，显式模式优先。
void main() {
  ReadingMode resolve({
    ReaderModeChoice mode = ReaderModeChoice.auto,
    TabletLayoutChoice tabletLayout = TabletLayoutChoice.auto,
    ReadingDirection direction = ReadingDirection.leftToRight,
    bool landscape = false,
    bool tablet = true,
  }) => resolveReaderMode(
    mode: mode,
    tabletLayout: tabletLayout,
    direction: direction,
    landscape: landscape,
    tablet: tablet,
  );

  group('平板默认排版', () {
    test('auto：横屏双页、竖屏单页', () {
      expect(resolve(landscape: true), ReadingMode.doublePage);
      expect(resolve(landscape: false), ReadingMode.paged);
    });

    test('强制单页：横屏也单页', () {
      expect(
        resolve(tabletLayout: TabletLayoutChoice.single, landscape: true),
        ReadingMode.paged,
      );
    });

    test('强制双页：竖屏也双页', () {
      expect(
        resolve(tabletLayout: TabletLayoutChoice.double, landscape: false),
        ReadingMode.doublePage,
      );
    });
  });

  group('手机不受影响', () {
    test('强制双页在手机上无效（仍按 auto 的横竖屏规则）', () {
      expect(
        resolve(
          tabletLayout: TabletLayoutChoice.double,
          landscape: false,
          tablet: false,
        ),
        ReadingMode.paged,
      );
      expect(
        resolve(
          tabletLayout: TabletLayoutChoice.single,
          landscape: true,
          tablet: false,
        ),
        ReadingMode.doublePage,
      );
    });
  });

  group('显式模式优先（系列/书覆盖）', () {
    test('显式单页压过"平板默认双页"', () {
      expect(
        resolve(
          mode: ReaderModeChoice.single,
          tabletLayout: TabletLayoutChoice.double,
        ),
        ReadingMode.paged,
      );
    });

    test('显式纵向压过平板设置', () {
      expect(
        resolve(
          mode: ReaderModeChoice.vertical,
          tabletLayout: TabletLayoutChoice.double,
        ),
        ReadingMode.verticalScroll,
      );
    });

    test('条漫方向 + auto：纵向滚动，平板默认双页也不强改', () {
      expect(
        resolve(
          direction: ReadingDirection.webtoon,
          tabletLayout: TabletLayoutChoice.double,
        ),
        ReadingMode.doublePage,
        reason: '平板显式要双页时，连条漫也按双页——这是用户的选择',
      );
    });
  });

  group('偏好持久化', () {
    test('默认 auto，存档往返保留', () {
      const defaults = ReaderPrefs();
      expect(defaults.tabletLayout, TabletLayoutChoice.auto);

      final saved = defaults.copyWith(tabletLayout: TabletLayoutChoice.double);
      expect(saved.toJson()['tabletLayout'], 'double');
      final restored = ReaderPrefs.fromJson(saved.toJson());
      expect(restored.tabletLayout, TabletLayoutChoice.double);
      expect(restored, saved);
    });

    test('坏值回 auto', () {
      final restored = ReaderPrefs.fromJson(<String, Object?>{
        'tabletLayout': 'huge',
      });
      expect(restored.tabletLayout, TabletLayoutChoice.auto);
    });
  });
}
