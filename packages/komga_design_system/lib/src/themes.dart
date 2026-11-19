import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 主题工厂：light / dark / eink。
///
/// 墨水屏主题的关键差异（都必须是"减法"）：
/// - 零动画、零阴影、零圆角、无水波纹；
/// - 纯黑白高对比，不用品牌色；
/// - 字号偏大、触控区偏大。
abstract final class AppTheme {
  static const Color seed = Color(0xFF4F6BFF);
  static const Color einkInk = Color(0xFF000000);
  static const Color einkPaper = Color(0xFFFFFFFF);
  static const Color einkMuted = Color(0xFF3A3A3A);

  /// 这套主题是不是墨水屏主题。
  ///
  /// 判据是"无水波纹 + 纸色底 + 墨色前景"：墨水屏主题独有的组合。
  /// 动效 / 材质 / 形状 token 都靠它退化，页面里不需要自己再读设置。
  static bool isEink(ThemeData theme) =>
      theme.splashFactory == NoSplash.splashFactory &&
      theme.colorScheme.surface == einkPaper &&
      theme.colorScheme.onSurface == einkInk;

  static ThemeData light() => _base(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
  );

  static ThemeData dark() =>
      _base(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData eink() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: einkInk,
      onPrimary: einkPaper,
      secondary: einkInk,
      onSecondary: einkPaper,
      error: einkInk,
      onError: einkPaper,
      surface: einkPaper,
      onSurface: einkInk,
      onSurfaceVariant: einkMuted,
      outline: einkInk,
      outlineVariant: einkMuted,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: einkPaper,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.comfortable,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _NoTransitionsBuilder(),
          TargetPlatform.iOS: _NoTransitionsBuilder(),
        },
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: einkPaper,
        foregroundColor: einkInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: einkPaper,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: einkInk),
          borderRadius: BorderRadius.zero,
        ),
      ),
      // 墨水屏的输入框：不留白底，靠 1px 墨框划定边界（灰阶上没有"填充色差"）。
      inputDecorationTheme: const InputDecorationThemeData(
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: einkInk),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: einkInk),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: einkInk, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minTouch),
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: einkInk),
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: einkPaper,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: einkInk),
          borderRadius: BorderRadius.zero,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: einkInk,
        linearTrackColor: Color(0xFFCCCCCC),
      ),
      textTheme: _einkTextTheme(base.textTheme),
    );
  }

  static TextTheme _einkTextTheme(TextTheme base) => base.copyWith(
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: einkInk,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: einkInk,
    ),
    bodyMedium: base.bodyMedium?.copyWith(color: einkInk),
    bodySmall: base.bodySmall?.copyWith(color: einkMuted),
  );

  static ThemeData _base(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
      // iOS 式输入框：无描边的浅填充、12 圆角，聚焦时一圈主题色。
      // 搜索框（GlassSearchField）显式关掉填充，免得盖住玻璃底色。
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minTouch),
          shape: const StadiumBorder(),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: AppSizes.hairline,
        thickness: AppSizes.hairline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      // iOS 式侧滑转场（UI-P2-3）：Android 也用同一套——目标是"像 iOS 原生质感"，
      // 不是跟随平台默认。代价是 Android 的预测性返回手势退化成普通返回动画。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: IosSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: IosSlidePageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// iOS 式侧滑转场。
///
/// 为什么自己写：`material_ui`（本仓库的统一 Material 入口）只给了 M3 的
/// `ZoomPageTransitionsBuilder` / `FadeForwardsPageTransitionsBuilder`，
/// 没有 Cupertino 那个 builder；而 `package:flutter/cupertino.dart` 在
/// Flutter 3.47 之后已标记废弃（要求换成 `cupertino_ui`，属于新依赖）。
/// 这里只做"新页从左滑入 + 旧页以 30% 速度左移"这一层——正是 iOS 侧滑的观感主体。
///
/// **边缘右滑返回**：由页面层的 `EdgeSwipeBack` 补上（非墨水屏、非"减少动态效果"），
/// 不追求手指跟手的交互式动画；`cupertino.dart` 已废弃，不引 `cupertino_ui` 新依赖。
/// Android 的系统返回手势不受影响。
class IosSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const IosSlidePageTransitionsBuilder();

  /// 旧页往左移的比例：iOS 上是 1/3 左右，太多会显得两页在赛跑。
  static const double _parallax = 0.3;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 首个路由没有"从右边进来"这回事，直接给它，省一层重绘。
    if (route.isFirst) return child;
    final enter = animation.drive(
      Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    final leave = secondaryAnimation.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-_parallax, 0),
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    return SlideTransition(
      position: enter,
      child: SlideTransition(position: leave, child: child),
    );
  }
}

/// 墨水屏用的"无转场"。
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
