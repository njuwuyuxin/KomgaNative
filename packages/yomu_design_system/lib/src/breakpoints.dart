/// 窗口尺寸分级。
enum WindowSizeClass {
  compact,
  medium,
  expanded;

  static WindowSizeClass of(double width) {
    if (width >= 1024) return WindowSizeClass.expanded;
    if (width >= 600) return WindowSizeClass.medium;
    return WindowSizeClass.compact;
  }

  /// 书架网格列数。
  int get gridColumns => switch (this) {
    WindowSizeClass.compact => 2,
    WindowSizeClass.medium => 3,
    WindowSizeClass.expanded => 4,
  };

  /// 是否使用侧边导航（否则底部导航）。
  bool get useNavigationRail => this != WindowSizeClass.compact;
}
