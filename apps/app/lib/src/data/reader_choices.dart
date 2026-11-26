import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 用户在阅读设置里选的模式。
///
/// 多一个 `auto` 是必要的：系列元数据能表达"条漫/竖向"，但表达不了"双页"。
/// `auto` 让"没选过"的用户跟随服务端元数据，选过的用户才有稳定的个人偏好。
enum ReaderModeChoice { auto, single, double, vertical }

extension ReaderModeChoiceX on ReaderModeChoice {
  /// 解析成引擎的阅读模式。
  ///
  /// `auto` 在竖屏跟随系列方向（条漫/竖向 → 纵向，其余单页）；
  /// **横屏时普通漫画自动双页**（Panels 的 Standard 预设行为，UI-P3-3）。
  /// 用户显式选过单页/双页/纵向则不受横竖屏影响。
  ReadingMode resolve(ReadingDirection direction, {bool landscape = false}) =>
      switch (this) {
        ReaderModeChoice.auto =>
          direction.isScroll
              ? ReadingMode.verticalScroll
              : (landscape ? ReadingMode.doublePage : ReadingMode.paged),
        ReaderModeChoice.single => ReadingMode.paged,
        ReaderModeChoice.double => ReadingMode.doublePage,
        ReaderModeChoice.vertical => ReadingMode.verticalScroll,
      };
}

/// 平板上的默认排版（PLT-02）。
///
/// `auto` = 横屏双页、竖屏单页（也就是现有行为）；`single`/`double` 强制一种。
/// **只在平板上生效**：手机上保持"跟随书籍方向 + 横屏自动双页"的老规矩，
/// 否则用户在设置里选过双页，回到手机就再也看不到单页了。
enum TabletLayoutChoice { auto, single, double }

/// 解析本次阅读真正用的模式（纯函数，单测直接钉住）。
///
/// 优先级（从高到低）：
/// 1. 用户显式选过阅读模式（单页/双页/纵向）——不管在哪、横竖屏都不改；
/// 2. 平板默认排版（`tabletLayout != auto`）；
/// 3. `auto`：跟随方向，横屏双页。
ReadingMode resolveReaderMode({
  required ReaderModeChoice mode,
  required TabletLayoutChoice tabletLayout,
  required ReadingDirection direction,
  required bool landscape,
  required bool tablet,
}) {
  if (mode != ReaderModeChoice.auto) {
    return mode.resolve(direction, landscape: landscape);
  }
  if (tablet && tabletLayout != TabletLayoutChoice.auto) {
    return tabletLayout == TabletLayoutChoice.double
        ? ReadingMode.doublePage
        : ReadingMode.paged;
  }
  return mode.resolve(direction, landscape: landscape);
}

/// 适配方式（UI-P1-3）。
enum ReaderFitChoice { contain, cover, fitWidth, fitHeight }

extension ReaderFitChoiceX on ReaderFitChoice {
  FitMode get fit => switch (this) {
    ReaderFitChoice.contain => FitMode.contain,
    ReaderFitChoice.cover => FitMode.cover,
    ReaderFitChoice.fitWidth => FitMode.fitWidth,
    ReaderFitChoice.fitHeight => FitMode.fitHeight,
  };
}

/// 阅读方向（UI-P1-4）。
enum ReaderDirectionChoice { auto, leftToRight, rightToLeft }

extension ReaderDirectionChoiceX on ReaderDirectionChoice {
  /// 解析成"是否右到左"。系列方向未知（`unknown`）时按从左到右。
  bool resolveRightToLeft(ReadingDirection series) => switch (this) {
    ReaderDirectionChoice.auto => series.isRightToLeft,
    ReaderDirectionChoice.leftToRight => false,
    ReaderDirectionChoice.rightToLeft => true,
  };
}

/// 阅读区背景（UI-P1-5）。
enum ReaderBackgroundChoice { black, white, dynamic, immersive }

/// 翻页动画（RDR-05）。
enum ReaderPageTurnChoice { curl, slide, fade, none }

/// 阅读设置的分组（RDR-04）。
enum ReaderSettingsGroup { pages, layout, color, interaction }

/// 按名字解析枚举；不是已知名字（旧版本 / 手工改坏）就回默认值。
T parseReaderEnum<T extends Enum>(Object? raw, List<T> values, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}
