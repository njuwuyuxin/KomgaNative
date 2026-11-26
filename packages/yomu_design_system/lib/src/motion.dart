import 'package:yomu_design_system/src/themes.dart';
import 'package:material_ui/material_ui.dart';

/// 动效 token：时长、曲线、弹簧，以及墨水屏 / "减少动态效果"的统一退化。
///
/// 规则：
/// - app 里的动画只从这里取值，页面里不写 `Duration(milliseconds: …)`；
/// - 一律经过 [AppMotion.of] 拿到"已退化"的值——墨水屏或系统开启"减少动态效果"时，
///   时长为 0、曲线为线性、弹簧瞬时到位，调用方不需要自己再判断一遍。
///
/// 数值取向接近 iOS：短交互约 150ms、常规过渡约 300ms、页面级约 450ms；
/// 弹簧用"临界阻尼附近"的手感（不明显回弹，但收尾柔和）。
@immutable
class AppMotion {
  const AppMotion._({
    required this.quick,
    required this.standard,
    required this.emphasized,
    required this.shimmer,
    required this.standardCurve,
    required this.emphasizedCurve,
    required this.exitCurve,
    required this.snappy,
    required this.gentle,
    required this.enabled,
  });

  /// 按下反馈、小图标切换。
  final Duration quick;

  /// chrome 显隐、面板内状态切换。
  final Duration standard;

  /// 页面级过渡、共享元素。
  final Duration emphasized;

  /// 骨架屏微光扫过一轮的时长（UI-P2-8）。
  final Duration shimmer;

  /// 进入 / 常规过渡：快起慢收。
  final Curve standardCurve;

  /// 强调过渡：收尾带极轻微的过冲。
  final Curve emphasizedCurve;

  /// 退出：慢起快收（元素离场不拖泥带水）。
  final Curve exitCurve;

  /// 界面元素（按压回弹、开关）的弹簧。
  final SpringDescription snappy;

  /// 页面级（缩放复位、面板落位）的弹簧。
  final SpringDescription gentle;

  /// 是否播放动画；墨水屏 / 减少动态效果时为 false。
  final bool enabled;

  /// 正常设备上的取值。
  static const AppMotion standardMotion = AppMotion._(
    quick: Duration(milliseconds: 150),
    standard: Duration(milliseconds: 300),
    emphasized: Duration(milliseconds: 450),
    shimmer: Duration(milliseconds: 1400),
    standardCurve: Curves.easeOutCubic,
    emphasizedCurve: Cubic(0.2, 0.9, 0.25, 1.05),
    exitCurve: Curves.easeInCubic,
    snappy: SpringDescription(mass: 1, stiffness: 520, damping: 42),
    gentle: SpringDescription(mass: 1, stiffness: 240, damping: 30),
    enabled: true,
  );

  /// 墨水屏 / 减少动态效果：零时长、线性、瞬时弹簧。
  ///
  /// 弹簧不能是"刚度无穷大"（模拟器会发散），这里给一个极硬、过阻尼的值，
  /// 但调用方看到 [enabled] 为 false 时应该直接跳到终值，不跑模拟。
  static const AppMotion reduced = AppMotion._(
    quick: Duration.zero,
    standard: Duration.zero,
    emphasized: Duration.zero,
    shimmer: Duration(milliseconds: 1400),
    standardCurve: Curves.linear,
    emphasizedCurve: Curves.linear,
    exitCurve: Curves.linear,
    snappy: SpringDescription(mass: 1, stiffness: 10000, damping: 400),
    gentle: SpringDescription(mass: 1, stiffness: 10000, damping: 400),
    enabled: false,
  );

  /// 纯函数版本：便于在没有 `BuildContext` 的地方（单测、控制器）使用。
  static AppMotion resolve({
    required bool eink,
    bool disableAnimations = false,
  }) => (eink || disableAnimations) ? reduced : standardMotion;

  /// 从上下文取：主题是否墨水屏（见 [AppTheme.isEink]）+ 系统"减少动态效果"。
  static AppMotion of(BuildContext context) => resolve(
    eink: AppTheme.isEink(Theme.of(context)),
    disableAnimations: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );
}
