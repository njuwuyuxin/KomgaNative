import 'package:material_ui/material_ui.dart';

/// 字体排印 token。
///
/// 只定义**层级和字重/字距**，不定死字号：字号来自主题的 `TextTheme`
/// （跟随系统字号缩放），这里在它上面做 iOS 式的调整——
/// 大标题更粗、字距收紧；正文略松；页码用等宽数字（翻页时宽度不跳）。
///
/// 中文字体：目前沿用系统字体（见 docs/adr/0004-cjk-font.md 的结论）。
@immutable
class AppTypography {
  const AppTypography._(this._base);

  factory AppTypography.of(BuildContext context) =>
      AppTypography._(Theme.of(context).textTheme);

  /// 测试 / 无上下文时用。
  factory AppTypography.fromTextTheme(TextTheme base) => AppTypography._(base);

  final TextTheme _base;

  /// 等宽数字：页码、计数、进度。
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// 页面大标题（书架、设置的折叠标题）。
  TextStyle get largeTitle =>
      _require(_base.headlineMedium)
          .copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5);

  /// 区块标题（"继续阅读"、详情页分组）。
  TextStyle get title =>
      _require(_base.titleLarge)
          .copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2);

  /// 卡片标题（封面下的书名）。
  TextStyle get headline =>
      _require(_base.titleSmall).copyWith(fontWeight: FontWeight.w600);

  /// 正文。
  TextStyle get body => _require(_base.bodyMedium).copyWith(height: 1.4);

  /// 说明文字（作者、页数）。
  TextStyle get caption => _require(_base.bodySmall);

  /// 角标、标签。
  TextStyle get label =>
      _require(_base.labelSmall)
          .copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2);

  /// 页码：等宽数字，避免 `9 / 12` → `10 / 12` 时整行左右跳。
  TextStyle get pageNumber =>
      _require(_base.labelLarge).copyWith(fontFeatures: tabularFigures);

  /// 进度数字（UI-01）：等宽数字 + 中等字重。
  ///
  /// 用在"会原地变化的数字"上（页码、下载进度、已读 N / M）。
  /// 不用等宽的话数字一变宽度就跳，进度条旁边的文本会左右抖。
  TextStyle get progressNumber =>
      _require(_base.labelLarge)
          .copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w600);

  /// Material 的默认 `TextTheme` 每个层级都有值；为空说明主题被裁剪过，
  /// 退回一个空样式而不是崩溃（字号仍会继承 `DefaultTextStyle`）。
  static TextStyle _require(TextStyle? style) => style ?? const TextStyle();
}
