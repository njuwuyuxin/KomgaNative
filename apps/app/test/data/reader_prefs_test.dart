import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/widgets/reader_mode_text.dart';
import 'package:komga_native/src/widgets/reader_settings_rows.dart';
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

    test('适配 / 方向 / 背景的默认值：适应屏幕、跟随系列、黑色', () {
      const prefs = ReaderPrefs();
      expect(prefs.fit, ReaderFitChoice.contain);
      expect(prefs.direction, ReaderDirectionChoice.auto);
      expect(prefs.background, ReaderBackgroundChoice.black);
    });

    test('适配 / 方向 / 背景一起往返', () {
      const prefs = ReaderPrefs(
        fit: ReaderFitChoice.cover,
        direction: ReaderDirectionChoice.rightToLeft,
        background: ReaderBackgroundChoice.dynamic,
      );
      final parsed = ReaderPrefs.fromJson(prefs.toJson());
      expect(parsed.fit, ReaderFitChoice.cover);
      expect(parsed.direction, ReaderDirectionChoice.rightToLeft);
      expect(parsed.background, ReaderBackgroundChoice.dynamic);
    });

    test('未知的适配/方向/背景值回默认（旧版本存档不会崩）', () {
      final prefs = ReaderPrefs.fromJson(<String, Object?>{
        'fit': 'stretch',
        'direction': 'sideways',
        'background': 42,
      });
      expect(prefs.fit, ReaderFitChoice.contain);
      expect(prefs.direction, ReaderDirectionChoice.auto);
      expect(prefs.background, ReaderBackgroundChoice.black);
    });

    test('沉浸式背景 JSON 往返', () {
      const prefs = ReaderPrefs(background: ReaderBackgroundChoice.immersive);
      expect(
        ReaderPrefs.fromJson(prefs.toJson()).background,
        ReaderBackgroundChoice.immersive,
      );
    });

    test('预设 JSON 往返：预设里的 prefs 不再带预设（不递归）', () {
      const preset = ReaderPreset(
        id: 'p1',
        name: 'Manga',
        prefs: ReaderPrefs(
          mode: ReaderModeChoice.double,
          fit: ReaderFitChoice.cover,
        ),
      );
      const prefs = ReaderPrefs(presets: <ReaderPreset>[preset]);
      final parsed = ReaderPrefs.fromJson(prefs.toJson());
      expect(parsed, prefs);
      expect(parsed.presets, hasLength(1));
      expect(parsed.presets.single.name, 'Manga');
      expect(parsed.presets.single.prefs.mode, ReaderModeChoice.double);
      expect(parsed.presets.single.prefs.presets, isEmpty);
    });

    test('坏预设条目跳过，好的保留', () {
      final parsed = ReaderPrefs.fromJson(<String, Object?>{
        'presets': <Object?>[
          <String, Object?>{
            'id': '',
            'name': 'x',
            'prefs': <String, Object?>{},
          },
          <String, Object?>{
            'id': 'p2',
            'name': '  ',
            'prefs': <String, Object?>{},
          },
          <String, Object?>{'id': 'p3', 'name': 'Q', 'prefs': 'bad'},
          <String, Object?>{
            'id': 'p4',
            'name': 'Good',
            'prefs': <String, Object?>{},
          },
        ],
      });
      expect(parsed.presets.map((ReaderPreset p) => p.name), <String>['Good']);
    });

    test('系列覆盖 JSON 往返：forSeries 优先，覆盖里不再嵌套', () {
      const prefs = ReaderPrefs(
        mode: ReaderModeChoice.single,
        seriesOverrides: <String, ReaderPrefs>{
          's1': ReaderPrefs(mode: ReaderModeChoice.double),
        },
      );
      final parsed = ReaderPrefs.fromJson(prefs.toJson());
      expect(parsed.forSeries('s1').mode, ReaderModeChoice.double);
      expect(parsed.forSeries('s2').mode, ReaderModeChoice.single);
      expect(parsed.seriesOverrides['s1']!.presets, isEmpty);
      expect(parsed.seriesOverrides['s1']!.seriesOverrides, isEmpty);
    });

    test('锁定缩放默认关、JSON 往返、系列覆盖可带', () {
      expect(const ReaderPrefs().lockZoom, isFalse);
      expect(
        ReaderPrefs.fromJson(<String, Object?>{'lockZoom': true}).lockZoom,
        isTrue,
      );
      const prefs = ReaderPrefs(
        lockZoom: true,
        seriesOverrides: <String, ReaderPrefs>{
          's1': ReaderPrefs(lockZoom: true),
        },
      );
      final parsed = ReaderPrefs.fromJson(prefs.toJson());
      expect(parsed.lockZoom, isTrue);
      expect(parsed.forSeries('s1').lockZoom, isTrue);
    });

    test('去白边默认关、JSON 往返、系列覆盖可带', () {
      expect(const ReaderPrefs().trimBorders, isFalse);
      expect(
        ReaderPrefs.fromJson(<String, Object?>{'trimBorders': true})
            .trimBorders,
        isTrue,
      );
      const prefs = ReaderPrefs(
        trimBorders: true,
        seriesOverrides: <String, ReaderPrefs>{
          's1': ReaderPrefs(trimBorders: true),
        },
      );
      final parsed = ReaderPrefs.fromJson(prefs.toJson());
      expect(parsed.trimBorders, isTrue);
      expect(parsed.forSeries('s1').trimBorders, isTrue);
    });
  });

  group('ReaderFitChoice → FitMode', () {
    test('四档一一对应，没有遗漏', () {
      expect(ReaderFitChoice.contain.fit, FitMode.contain);
      expect(ReaderFitChoice.cover.fit, FitMode.cover);
      expect(ReaderFitChoice.fitWidth.fit, FitMode.fitWidth);
      expect(ReaderFitChoice.fitHeight.fit, FitMode.fitHeight);
      expect(
        ReaderFitChoice.values.map((ReaderFitChoice c) => c.fit).toSet(),
        hasLength(ReaderFitChoice.values.length),
      );
    });
  });

  group('ReaderDirectionChoice.resolveRightToLeft', () {
    test('auto 跟随系列，其余两项强制', () {
      expect(
        ReaderDirectionChoice.auto.resolveRightToLeft(
          ReadingDirection.rightToLeft,
        ),
        isTrue,
      );
      expect(
        ReaderDirectionChoice.auto.resolveRightToLeft(
          ReadingDirection.leftToRight,
        ),
        isFalse,
      );
      // 系列没填方向时按从左到右（LTR 是阅读器里最常见的默认）。
      expect(
        ReaderDirectionChoice.auto.resolveRightToLeft(ReadingDirection.unknown),
        isFalse,
      );
      expect(
        ReaderDirectionChoice.leftToRight.resolveRightToLeft(
          ReadingDirection.rightToLeft,
        ),
        isFalse,
      );
      expect(
        ReaderDirectionChoice.rightToLeft.resolveRightToLeft(
          ReadingDirection.leftToRight,
        ),
        isTrue,
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

    test('auto 横屏自动双页；条漫仍纵向；显式选择不受横屏影响', () {
      expect(
        ReaderModeChoice.auto.resolve(
          ReadingDirection.rightToLeft,
          landscape: true,
        ),
        ReadingMode.doublePage,
      );
      expect(
        ReaderModeChoice.auto.resolve(
          ReadingDirection.webtoon,
          landscape: true,
        ),
        ReadingMode.verticalScroll,
      );
      expect(
        ReaderModeChoice.single.resolve(
          ReadingDirection.rightToLeft,
          landscape: true,
        ),
        ReadingMode.paged,
      );
      expect(
        ReaderModeChoice.vertical.resolve(
          ReadingDirection.rightToLeft,
          landscape: true,
        ),
        ReadingMode.verticalScroll,
      );
    });

    test('每种选择都有中英文标签与说明（面板上不能出现空行）', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      for (final choice in ReaderModeChoice.values) {
        expect(readerModeLabel(en, choice), isNotEmpty);
        expect(readerModeHint(en, choice), isNotEmpty);
        expect(readerModeLabel(zh, choice), isNotEmpty);
        expect(readerModeHint(zh, choice), isNotEmpty);
        expect(readerModeLabel(en, choice), isNot(readerModeLabel(zh, choice)));
      }
    });
  });

  group('新增三组设置的文案', () {
    test('适配 / 方向 / 背景都有中英文标签与说明', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      for (final choice in ReaderFitChoice.values) {
        expect(readerFitLabel(en, choice), isNotEmpty);
        expect(readerFitHint(en, choice), isNotEmpty);
        expect(readerFitLabel(zh, choice), isNotEmpty);
        expect(readerFitHint(zh, choice), isNotEmpty);
      }
      for (final choice in ReaderDirectionChoice.values) {
        expect(readerDirectionLabel(en, choice), isNotEmpty);
        expect(readerDirectionHint(en, choice), isNotEmpty);
        expect(readerDirectionLabel(zh, choice), isNotEmpty);
        expect(readerDirectionHint(zh, choice), isNotEmpty);
      }
      for (final choice in ReaderBackgroundChoice.values) {
        expect(readerBackgroundLabel(en, choice), isNotEmpty);
        expect(readerBackgroundHint(en, choice), isNotEmpty);
        expect(readerBackgroundLabel(zh, choice), isNotEmpty);
        expect(readerBackgroundHint(zh, choice), isNotEmpty);
      }
    });
  });
}
