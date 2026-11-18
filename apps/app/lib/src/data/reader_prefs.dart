import 'package:komga_domain/komga_domain.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

/// 用户在阅读设置里选的模式。
///
/// 多一个 `auto` 是必要的：系列元数据能表达"条漫/竖向"，但表达不了"双页"。
/// `auto` 让"没选过"的用户跟随服务端元数据，选过的用户才有稳定的个人偏好。
enum ReaderModeChoice { auto, single, double, vertical }

extension ReaderModeChoiceX on ReaderModeChoice {
  /// 解析成引擎的阅读模式。
  ReadingMode resolve(ReadingDirection direction) => switch (this) {
    ReaderModeChoice.auto =>
      direction.isScroll ? ReadingMode.verticalScroll : ReadingMode.paged,
    ReaderModeChoice.single => ReadingMode.paged,
    ReaderModeChoice.double => ReadingMode.doublePage,
    ReaderModeChoice.vertical => ReadingMode.verticalScroll,
  };
}

/// 适配方式（UI-P1-3）。
///
/// 直接对应引擎的 `FitMode`：`cover`（填满屏幕）会在溢出的方向允许平移，
/// 双页模式一律按 `contain`（一跨页两页并排，任何"铺满"都会把另一页裁掉）。
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
///
/// `auto` 跟随系列元数据；另两项给"元数据没填 / 填错"的书兜底。
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
///
/// `dynamic` 从当前页边缘提色，双页取两页的平均；墨水屏不提供这一项（固定白底）。
enum ReaderBackgroundChoice { black, white, dynamic }

/// 阅读器偏好（全局，不分书）。
///
/// 为什么不分书：漫画是"一次读很多卷"的场景，每本都要重设模式反而烦；
/// 而"条漫 vs 单行本"的差异已经由系列元数据 + [ReaderModeChoice.auto] 兜住了。
class ReaderPrefs {
  const ReaderPrefs({
    this.mode = ReaderModeChoice.auto,
    this.brightness = 1,
    this.keepAwake = false,
    this.fit = ReaderFitChoice.contain,
    this.direction = ReaderDirectionChoice.auto,
    this.background = ReaderBackgroundChoice.black,
  });

  /// 亮度下限：再暗也要能看见字，所以不允许 0。
  static const double minBrightness = 0.2;

  final ReaderModeChoice mode;

  /// 1 = 不遮罩；小于 1 时在阅读区上盖一层半透明黑。
  final double brightness;

  final bool keepAwake;

  final ReaderFitChoice fit;
  final ReaderDirectionChoice direction;
  final ReaderBackgroundChoice background;

  /// 遮罩的不透明度（亮度越低盖得越黑）。
  double get dimOpacity => (1 - brightness).clamp(0.0, 1 - minBrightness);

  ReaderPrefs copyWith({
    ReaderModeChoice? mode,
    double? brightness,
    bool? keepAwake,
    ReaderFitChoice? fit,
    ReaderDirectionChoice? direction,
    ReaderBackgroundChoice? background,
  }) => ReaderPrefs(
    mode: mode ?? this.mode,
    brightness: brightness ?? this.brightness,
    keepAwake: keepAwake ?? this.keepAwake,
    fit: fit ?? this.fit,
    direction: direction ?? this.direction,
    background: background ?? this.background,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'brightness': brightness,
    'keepAwake': keepAwake,
    'fit': fit.name,
    'direction': direction.name,
    'background': background.name,
  };

  /// 存档可能被旧版本/手工改过，所有字段先判类型再取值，坏值一律回默认，
  /// 绝不让一条脏数据把阅读器变成黑屏或抛异常。
  static ReaderPrefs fromJson(Map<String, Object?> json) {
    final rawBrightness = json['brightness'];
    final brightness = rawBrightness is num
        ? rawBrightness.toDouble().clamp(minBrightness, 1.0)
        : 1.0;
    return ReaderPrefs(
      mode: _parse(
        json['mode'],
        ReaderModeChoice.values,
        ReaderModeChoice.auto,
      ),
      brightness: brightness,
      keepAwake: json['keepAwake'] == true,
      fit: _parse(json['fit'], ReaderFitChoice.values, ReaderFitChoice.contain),
      direction: _parse(
        json['direction'],
        ReaderDirectionChoice.values,
        ReaderDirectionChoice.auto,
      ),
      background: _parse(
        json['background'],
        ReaderBackgroundChoice.values,
        ReaderBackgroundChoice.black,
      ),
    );
  }

  /// 按名字解析枚举；不是已知名字（旧版本 / 手工改坏）就回默认值。
  static T _parse<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.mode == mode &&
      other.brightness == brightness &&
      other.keepAwake == keepAwake &&
      other.fit == fit &&
      other.direction == direction &&
      other.background == background;

  @override
  int get hashCode =>
      Object.hash(mode, brightness, keepAwake, fit, direction, background);

  @override
  String toString() =>
      'ReaderPrefs(${mode.name}, $brightness, $keepAwake, ${fit.name}, '
      '${direction.name}, ${background.name})';
}
