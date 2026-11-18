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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
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
