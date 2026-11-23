import 'dart:ui' show ImageFilter;

import 'package:komga_design_system/src/glass_optics.dart';
import 'package:komga_design_system/src/themes.dart';
import 'package:material_ui/material_ui.dart';

/// 材质 token：毛玻璃（模糊 + 半透明底色）。
///
/// 三种用途对应三档：
/// - [chrome]：阅读器顶栏 / 底栏，压在漫画画面上，要最强的模糊和较深的底色，
///   保证任何画面上文字都可读；
/// - [bar]：普通页面的导航栏 / 标题栏，滚动内容从下面穿过。
///   这一档是 iOS 26 "液态玻璃"：更透、提饱和，并带 [GlassOptics]
///   （边缘折射、内缘聚光、镜面高光边，由 `FrostedSurface` 画出来）；
/// - [sheet]：底部面板。
///
/// 墨水屏：不模糊（刷新成本高、残影），改成不透明纸色底 + 1px 墨色描边，
/// 由 [AppMaterial.resolve] 统一退化。
enum AppMaterialKind { chrome, bar, sheet }

@immutable
class AppMaterial {
  const AppMaterial({
    required this.blurSigma,
    required this.tint,
    this.border,
    this.highlight,
    this.optics,
  });

  /// 液态玻璃的光学参数（饱和、内缘聚光、镜面高光边、内阴影）。
  ///
  /// 只给彩色主题的 [AppMaterialKind.bar]；为 null 时就是普通毛玻璃。
  final GlassOptics? optics;

  /// 高斯模糊半径（逻辑像素）；0 = 不模糊。
  final double blurSigma;

  /// 叠在模糊之上的底色（带透明度）。
  final Color tint;

  /// 描边：墨水屏是 1px 墨线；液态玻璃的边由 [optics] 画（带方向的高光）。
  final BorderSide? border;

  /// 玻璃体内反光：压在底色之上、自上而下的柔和渐变。
  ///
  /// 只给彩色主题的 [AppMaterialKind.bar]；由 `FrostedSurface` 叠在模糊层之上。
  /// 墨水屏为 null——灰阶上那层白只会变成一团脏灰。
  final Gradient? highlight;

  bool get blurs => blurSigma > 0;

  /// 背景滤镜：先模糊，玻璃档再把模糊结果的饱和度拉高
  /// （iOS 液态玻璃"背后颜色更鲜"的来源，不提饱和就是一块灰磨砂）。
  ImageFilter? get filter {
    if (!blurs) return null;
    final blur = ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);
    final saturation = optics?.saturation ?? 1;
    if (saturation == 1) return blur;
    return ImageFilter.compose(
      outer: ColorFilter.matrix(GlassOptics.saturationMatrix(saturation)),
      inner: blur,
    );
  }

  /// 按可见度缩放的背景滤镜：避免在 `BackdropFilter` 外层套 `Opacity`
  /// （`OpacityLayer` 会隔断背景读取，动画结尾 `opacity == 1` 撤掉离屏层时产生跳变）。
  ImageFilter? filterForOpacity(double opacity) {
    final t = opacity.clamp(0.0, 1.0);
    if (t >= 1) return filter;
    final sigma = blurSigma * t;
    if (sigma <= 0.05) return null;
    final blur = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    final rawSaturation = optics?.saturation ?? 1;
    final saturation = 1 + (rawSaturation - 1) * t;
    if ((saturation - 1).abs() < 0.01) return blur;
    return ImageFilter.compose(
      outer: ColorFilter.matrix(GlassOptics.saturationMatrix(saturation)),
      inner: blur,
    );
  }

  /// 按主题取一种材质。
  ///
  /// [dark] 指的是"材质压在什么上面"：阅读器 chrome 永远压在画面上，
  /// 不论系统深浅色都用深色材质（iOS 照片 / 图书的做法）。
  static AppMaterial resolve(
    AppMaterialKind kind, {
    required bool eink,
    required bool dark,
  }) {
    if (eink) {
      return const AppMaterial(
        blurSigma: 0,
        tint: AppTheme.einkPaper,
        border: BorderSide(color: AppTheme.einkInk),
      );
    }
    return switch ((kind, dark)) {
      (AppMaterialKind.chrome, _) => const AppMaterial(
        blurSigma: 24,
        tint: Color(0xB8121214),
      ),
      // 液态玻璃（iOS 26）：模糊比磨砂轻、底色更透、背后颜色提饱和；
      // "玻璃感"交给 [GlassOptics]：内缘聚光 + 斜对角镜面高光边 + 底部内阴影。
      // 底色 60% 是可读性的下限：再透，标签在彩色封面上就不够读了
      // （`library_nav@phone_light` 基线里有对照）。
      (AppMaterialKind.bar, true) => const AppMaterial(
        blurSigma: 14,
        tint: Color(0x991C1C1E),
        highlight: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x1FFFFFFF),
            Color(0x05FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: <double>[0, 0.5, 1],
        ),
        optics: GlassOptics.dark,
      ),
      (AppMaterialKind.bar, false) => const AppMaterial(
        blurSigma: 14,
        tint: Color(0x99F8F8FA),
        highlight: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x4DFFFFFF),
            Color(0x0DFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: <double>[0, 0.5, 1],
        ),
        optics: GlassOptics.light,
      ),
      (AppMaterialKind.sheet, true) => const AppMaterial(
        blurSigma: 30,
        tint: Color(0xE01C1C1E),
      ),
      (AppMaterialKind.sheet, false) => const AppMaterial(
        blurSigma: 30,
        tint: Color(0xEBF2F2F7),
      ),
    };
  }

  /// 从上下文取：墨水屏判断看主题，深浅色看 `Theme.brightness`。
  static AppMaterial of(BuildContext context, AppMaterialKind kind) {
    final theme = Theme.of(context);
    return resolve(
      kind,
      eink: AppTheme.isEink(theme),
      dark: theme.brightness == Brightness.dark,
    );
  }
}

/// 阴影 token：大半径、低透明度、向下偏移——"浮在纸上"，不是 Material 的硬投影。
///
/// 墨水屏一律无阴影（灰阶屏上只会变成一团脏灰）。
abstract final class AppShadows {
  /// 封面：贴近书架的柔和投影 + 一圈极淡的接触阴影。
  static const List<BoxShadow> cover = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x24000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// 卡片：比封面更轻。
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// 浮层（菜单、浮动按钮）。深色主题用这一组。
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x2E000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// 浅色主题的浮层阴影：更淡、更短。
  ///
  /// 白底上的 0x2E 大阴影会糊成一圈灰边，看起来像"脏"而不是"浮起来"
  /// （UI-01：降低浅色模式 floating 阴影）。
  static const List<BoxShadow> floatingLight = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// 按当前主题取浮层阴影：浅色更淡，墨水屏清零。
  static List<BoxShadow> floatingOf(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return of(context, dark ? floating : floatingLight);
  }

  static const List<BoxShadow> none = <BoxShadow>[];

  /// 选中封面时的柔和主题色光晕投影：不用硬线框，靠主色弥散光晕 + 轻接触影托出选中感。
  ///
  /// 墨水屏返回 [none]。
  static List<BoxShadow> selectedCover(
    BuildContext context, {
    required Color color,
  }) {
    final theme = Theme.of(context);
    return resolveSelectedCover(
      color,
      eink: AppTheme.isEink(theme),
      dark: theme.brightness == Brightness.dark,
    );
  }

  /// 纯函数版本，便于单测验证深浅色与墨水屏退化。
  static List<BoxShadow> resolveSelectedCover(
    Color color, {
    required bool eink,
    required bool dark,
  }) {
    if (eink) return none;
    return <BoxShadow>[
      BoxShadow(
        color: Color(dark ? 0x33000000 : 0x1A000000),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
      BoxShadow(
        color: color.withValues(alpha: dark ? 0.28 : 0.22),
        blurRadius: 16,
      ),
    ];
  }

  /// 按主题退化：墨水屏返回 [none]。
  static List<BoxShadow> resolve(
    List<BoxShadow> shadow, {
    required bool eink,
  }) => eink ? none : shadow;

  static List<BoxShadow> of(BuildContext context, List<BoxShadow> shadow) =>
      resolve(shadow, eink: AppTheme.isEink(Theme.of(context)));
}
