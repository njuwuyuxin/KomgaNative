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

/// 阅读器偏好（全局，不分书）。
///
/// 为什么不分书：漫画是"一次读很多卷"的场景，每本都要重设模式反而烦；
/// 而"条漫 vs 单行本"的差异已经由系列元数据 + [ReaderModeChoice.auto] 兜住了。
class ReaderPrefs {
  const ReaderPrefs({
    this.mode = ReaderModeChoice.auto,
    this.brightness = 1,
    this.keepAwake = false,
  });

  /// 亮度下限：再暗也要能看见字，所以不允许 0。
  static const double minBrightness = 0.2;

  final ReaderModeChoice mode;

  /// 1 = 不遮罩；小于 1 时在阅读区上盖一层半透明黑。
  final double brightness;

  final bool keepAwake;

  /// 遮罩的不透明度（亮度越低盖得越黑）。
  double get dimOpacity => (1 - brightness).clamp(0.0, 1 - minBrightness);

  ReaderPrefs copyWith({
    ReaderModeChoice? mode,
    double? brightness,
    bool? keepAwake,
  }) => ReaderPrefs(
    mode: mode ?? this.mode,
    brightness: brightness ?? this.brightness,
    keepAwake: keepAwake ?? this.keepAwake,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'brightness': brightness,
    'keepAwake': keepAwake,
  };

  /// 存档可能被旧版本/手工改过，所有字段先判类型再取值，坏值一律回默认，
  /// 绝不让一条脏数据把阅读器变成黑屏或抛异常。
  static ReaderPrefs fromJson(Map<String, Object?> json) {
    final rawMode = json['mode'];
    final mode = ReaderModeChoice.values.firstWhere(
      (ReaderModeChoice value) => value.name == rawMode,
      orElse: () => ReaderModeChoice.auto,
    );
    final rawBrightness = json['brightness'];
    final brightness = rawBrightness is num
        ? rawBrightness.toDouble().clamp(minBrightness, 1.0)
        : 1.0;
    return ReaderPrefs(
      mode: mode,
      brightness: brightness,
      keepAwake: json['keepAwake'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.mode == mode &&
      other.brightness == brightness &&
      other.keepAwake == keepAwake;

  @override
  int get hashCode => Object.hash(mode, brightness, keepAwake);

  @override
  String toString() => 'ReaderPrefs(${mode.name}, $brightness, $keepAwake)';
}
