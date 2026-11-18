import 'dart:ui' show ImageFilter;

import 'package:komga_design_system/src/themes.dart';
import 'package:material_ui/material_ui.dart';

/// 材质 token：毛玻璃（模糊 + 半透明底色）。
///
/// 三种用途对应三档：
/// - [chrome]：阅读器顶栏 / 底栏，压在漫画画面上，要最强的模糊和较深的底色，
///   保证任何画面上文字都可读；
/// - [bar]：普通页面的导航栏 / 标题栏，滚动内容从下面穿过；
/// - [sheet]：底部面板。
///
/// 墨水屏：不模糊（刷新成本高、残影），改成不透明纸色底 + 1px 墨色描边，
/// 由 [AppMaterial.resolve] 统一退化。
enum AppMaterialKind { chrome, bar, sheet }

@immutable
class AppMaterial {
  const AppMaterial({required this.blurSigma, required this.tint, this.border});

  /// 高斯模糊半径（逻辑像素）；0 = 不模糊。
  final double blurSigma;

  /// 叠在模糊之上的底色（带透明度）。
  final Color tint;

  /// 描边（墨水屏用）。
  final BorderSide? border;

  bool get blurs => blurSigma > 0;

  ImageFilter? get filter =>
      blurs ? ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma) : null;

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
      (AppMaterialKind.bar, true) => const AppMaterial(
        blurSigma: 20,
        tint: Color(0xCC1C1C1E),
      ),
      (AppMaterialKind.bar, false) => const AppMaterial(
        blurSigma: 20,
        tint: Color(0xD9F9F9F9),
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

  /// 浮层（菜单、浮动按钮）。
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x2E000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  static const List<BoxShadow> none = <BoxShadow>[];

  /// 按主题退化：墨水屏返回 [none]。
  static List<BoxShadow> resolve(
    List<BoxShadow> shadow, {
    required bool eink,
  }) => eink ? none : shadow;

  static List<BoxShadow> of(BuildContext context, List<BoxShadow> shadow) =>
      resolve(shadow, eink: AppTheme.isEink(Theme.of(context)));
}
