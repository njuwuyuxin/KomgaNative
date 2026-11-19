import 'package:material_ui/material_ui.dart';

/// 间距标尺。页面只允许使用这些值。
abstract final class AppSpacing {
  /// 细线 / 角标内边距。
  static const double xxs = 2;
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

/// 圆角标尺（数值）。墨水屏主题会把它们压成 0（见 [AppTheme.eink]）。
///
/// 页面里优先用 [AppShapes]（连续曲率、会按主题退化）；只有必须给
/// `BorderRadius` 的老接口才直接用这里的数值。
abstract final class AppRadii {
  /// 封面：小圆角，像实体书的切边，而不是"卡片"。
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;

  /// 底部面板顶角。
  static const double xl = 28;
}

/// 图标与小尺寸控件标尺。
abstract final class AppSizes {
  /// 分隔线。
  static const double hairline = 1;

  /// 行内小图标（离线标记等）、按钮内的小转圈。
  static const double iconXs = 16;

  /// 状态图标（书末条的勾）。
  static const double iconSm = 18;

  /// 列表行尾图标、设置面板图标。
  static const double iconMd = 20;

  static const double iconLg = 24;

  /// 进度条粗细。
  static const double progressBar = 3;

  /// 最小触控尺寸（与 Material / HIG 一致）。
  static const double minTouch = 48;

  /// 底部面板顶部的拖动条。
  static const Size grabber = Size(36, 4);

  /// 悬浮玻璃导航条的胶囊高度（搜索圆球同高，所以是正方形）。
  static const double navBarHeight = 64;

  /// 页面滚动内容末尾为悬浮导航条留出的空白：条高 64 + 上方 16 + 下方 8，
  /// 再按最长的一档系统安全区（34）留足，避免最后一行被导航条压住。
  static const double navBarClearance = 112;

  /// 横向货架（继续阅读）里的封面。
  static const Size shelfCover = Size(96, 136);

  /// 横向货架整行高度：封面 + 两行文字。
  static const double shelfRowHeight = 196;

  /// 阅读器底部缩略图滑条里的单张缩略图。
  static const Size thumb = Size(36, 52);

  /// 缩略图滑条整行高度：缩略图 + 上下留白。
  static const double thumbStripHeight = 68;

  /// 卡片行里的小封面（书末"下一本"卡片）。
  static const Size rowCover = Size(44, 62);

  /// 表单里"标签：值"的标签列宽（证书面板）。
  static const double labelColumn = 92;

  /// 设置面板里滑条两端数值的宽度。
  static const double valueColumn = 44;
}

/// 布局断点，与 `komga_platform` 的形态判断保持同一套数值。
abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 1024;
}
