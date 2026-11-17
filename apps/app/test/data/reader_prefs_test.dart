import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

void main() {
  group('ReaderPrefs', () {
    test('默认跟随书（auto）、不调暗、不常亮', () {
      const prefs = ReaderPrefs();
      expect(prefs.mode, ReaderModeChoice.auto);
      expect(prefs.brightness, 1);
      expect(prefs.dimOpacity, 0);
      expect(prefs.keepAwake, isFalse);
    });

    test('亮度越低遮罩越黑，且不允许全黑', () {
      expect(const ReaderPrefs(brightness: 0.5).dimOpacity, closeTo(0.5, 1e-9));
      expect(
        const ReaderPrefs(brightness: ReaderPrefs.minBrightness).dimOpacity,
        closeTo(0.8, 1e-9),
      );
      // 就算存档里是 0，也不能变成全黑屏。
      expect(const ReaderPrefs(brightness: 0).dimOpacity, closeTo(0.8, 1e-9));
    });

    test('copyWith 只改指定字段', () {
      const prefs = ReaderPrefs(keepAwake: true);
      final next = prefs.copyWith(brightness: 0.6);
      expect(next.brightness, 0.6);
      expect(next.keepAwake, isTrue);
      expect(next.mode, ReaderModeChoice.auto);
    });

    test('JSON 往返', () {
      const prefs = ReaderPrefs(
        mode: ReaderModeChoice.double,
        brightness: 0.7,
        keepAwake: true,
      );
      expect(ReaderPrefs.fromJson(prefs.toJson()), prefs);
    });

    test('坏存档一律回默认，不让设置把阅读器弄坏', () {
      final prefs = ReaderPrefs.fromJson(<String, Object?>{
        'mode': 'triple', // 不认识的模式
        'brightness': '0.3', // 类型不对
        'keepAwake': 'yes', // 类型不对
      });
      expect(prefs.mode, ReaderModeChoice.auto);
      expect(prefs.brightness, 1);
      expect(prefs.keepAwake, isFalse);
    });

    test('亮度越界夹到 [min, 1]', () {
      expect(
        ReaderPrefs.fromJson(<String, Object?>{'brightness': 5}).brightness,
        1,
      );
      expect(
        ReaderPrefs.fromJson(<String, Object?>{'brightness': -2}).brightness,
        ReaderPrefs.minBrightness,
      );
    });
  });

  group('ReaderModeChoice.resolve', () {
    test('auto 跟随系列方向：条漫/竖向 → 纵向，其余 → 单页', () {
      expect(
        ReaderModeChoice.auto.resolve(ReadingDirection.webtoon),
        ReadingMode.verticalScroll,
      );
      expect(
        ReaderModeChoice.auto.resolve(ReadingDirection.vertical),
        ReadingMode.verticalScroll,
      );
      expect(
        ReaderModeChoice.auto.resolve(ReadingDirection.rightToLeft),
        ReadingMode.paged,
      );
      expect(
        ReaderModeChoice.auto.resolve(ReadingDirection.unknown),
        ReadingMode.paged,
      );
    });

    test('显式选择覆盖系列方向', () {
      expect(
        ReaderModeChoice.double.resolve(ReadingDirection.webtoon),
        ReadingMode.doublePage,
      );
      expect(
        ReaderModeChoice.single.resolve(ReadingDirection.vertical),
        ReadingMode.paged,
      );
      expect(
        ReaderModeChoice.vertical.resolve(ReadingDirection.rightToLeft),
        ReadingMode.verticalScroll,
      );
    });

    test('每种选择都有标签与说明（面板上不能出现空行）', () {
      for (final choice in ReaderModeChoice.values) {
        expect(choice.label, isNotEmpty);
        expect(choice.hint, isNotEmpty);
      }
    });
  });
}
