import 'package:flutter/services.dart';

/// 触感反馈的薄封装：三种语义 + 一个总开关。
///
/// 页面里不直接调 `HapticFeedback`：统一从这里走，设置页的"触感反馈"开关
/// 才能一处关掉；测试里也只需要断言调用了哪种语义。
///
/// 墨水屏保留触感反馈——它不影响屏幕刷新。
abstract final class AppHaptics {
  /// 总开关（由 app 根据设置同步）。
  static bool enabled = true;

  /// 选择变化：滑条经过一页、切换分段。
  static Future<void> selection() =>
      enabled ? HapticFeedback.selectionClick() : Future<void>.value();

  /// 轻触：按下卡片、打开菜单。
  static Future<void> light() =>
      enabled ? HapticFeedback.lightImpact() : Future<void>.value();

  /// 完成：读完一本、下载完成。
  static Future<void> success() =>
      enabled ? HapticFeedback.mediumImpact() : Future<void>.value();
}
