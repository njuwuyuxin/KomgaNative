import 'package:material_ui/material_ui.dart';

/// 间距标尺。页面只允许使用这些值。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );
}

/// 圆角标尺。墨水屏主题会把它们压成 0（见 [AppTheme.eink]）。
abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
}

/// 动效时长。
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);

  /// 墨水屏一律零时长，否则会拖影。
  static const Duration none = Duration.zero;

  static Duration resolve({required bool eink, Duration fallback = normal}) =>
      eink ? none : fallback;
}

/// 布局断点，与 `komga_platform` 的形态判断保持同一套数值。
abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 1024;
}
