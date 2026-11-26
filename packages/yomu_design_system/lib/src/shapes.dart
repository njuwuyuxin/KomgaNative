import 'package:yomu_design_system/src/themes.dart';
import 'package:yomu_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 形状 token：连续曲率圆角（squircle 近似）。
///
/// 用 Flutter 自带的 [ContinuousRectangleBorder]，不引第三方包。
/// 注意它的 `borderRadius` 语义与 [RoundedRectangleBorder] 不同：
/// 同样的数值，连续曲率的"视觉圆角"大约只有一半多一点，所以这里统一乘
/// [_continuousScale]，让 `AppRadii.md` 在两种形状上看起来差不多大。
///
/// 墨水屏：零圆角（直角更清晰，也与旧主题一致）。
abstract final class AppShapes {
  /// 连续曲率与普通圆角的视觉换算系数（经验值，见类注释）。
  static const double _continuousScale = 2.2;

  /// 封面：小圆角。
  static ShapeBorder cover({required bool eink}) => _shape(AppRadii.xs, eink);

  /// 卡片、列表行缩略图。
  static ShapeBorder card({required bool eink}) => _shape(AppRadii.md, eink);

  /// 大容器（面板、对话框）。
  static ShapeBorder panel({required bool eink}) => _shape(AppRadii.lg, eink);

  /// 悬浮导航条：胶囊形（iOS 26 的玻璃 tab bar）。
  ///
  /// 胶囊不需要连续曲率系数：端头本来就是半径 = 高度/2 的半圆，
  /// 用 [StadiumBorder] 比近似 squircle 更准确。墨水屏退化成直角。
  static ShapeBorder bar({required bool eink}) =>
      eink ? const RoundedRectangleBorder() : const StadiumBorder();

  /// 底部面板：只有顶部两个角是圆的。
  static ShapeBorder sheet({required bool eink}) => eink
      ? const RoundedRectangleBorder(side: BorderSide(color: AppTheme.einkInk))
      : const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        );

  /// 从上下文取（墨水屏看主题）。
  static ShapeBorder of(
    BuildContext context,
    ShapeBorder Function({required bool eink}) shape,
  ) => shape(eink: AppTheme.isEink(Theme.of(context)));

  static ShapeBorder _shape(double radius, bool eink) {
    if (eink) return const RoundedRectangleBorder();
    return ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(radius * _continuousScale),
    );
  }
}
