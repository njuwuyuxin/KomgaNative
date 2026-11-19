import 'package:material_ui/material_ui.dart';

/// 液态玻璃的光学参数（iOS 26 Liquid Glass 的合成近似）。
///
/// 一块液态玻璃由五层叠成，这里每层一个参数：
/// 1. **饱和**（[saturation]）：背后的模糊结果提饱和，颜色"透出来"而不是发灰；
/// 2. **边缘折射**（[refraction] / [refractionBand]）：靠外缘的一圈环带把
///    玻璃**外面**的内容拉进来（像透过厚玻璃侧面看），中间区域不动；
/// 3. **内缘聚光**（[rimLight] / [rimWidth]）：厚玻璃边缘把光聚在内侧的一圈柔光；
/// 4. **镜面高光边**（[specular] / [specularWidth]）：沿外轮廓一条细亮线，亮度随
///    方向变化——光从左上来：左上最亮，右下有一道反射，另外两侧暗；
/// 5. **轮廓**（[contour]）：浅色背景上靠它和阴影把玻璃"托"出来。
///
/// 只属于彩色主题的玻璃档（`AppMaterialKind.bar`）；墨水屏永远是 null。
@immutable
class GlassOptics {
  const GlassOptics({
    required this.saturation,
    required this.refraction,
    required this.refractionBand,
    required this.rimLight,
    required this.rimWidth,
    required this.specular,
    required this.specularWidth,
    required this.selectionFill,
    this.contour,
  });

  /// 玻璃里"选中项"那块嵌入胶囊的底色（中性灰/白，不染主色——
  /// iOS 26 的 tab bar 选中项是玻璃里再嵌一块亮玻璃，不是一块彩色塑料）。
  final Color selectionFill;

  /// 背后模糊结果的饱和度倍数；1 = 不变。
  final double saturation;

  /// 外缘处"拉进来"的距离（逻辑像素）：外缘那一像素显示的是玻璃外这么远的内容。
  /// 0 = 不折射。
  final double refraction;

  /// 折射环带的宽度（逻辑像素）：环带以内的内容不动。
  final double refractionBand;

  /// 内缘聚光的颜色（带透明度）。
  final Color rimLight;

  /// 内缘聚光向内渗透的距离（逻辑像素）。
  final double rimWidth;

  /// 镜面高光边沿方向的颜色：从正右（0°）开始**顺时针**每 45° 一个，
  /// 共 [specularStops] 个，首尾相同（闭环）。
  final List<Color> specular;

  /// 镜面高光边的线宽（逻辑像素）。
  final double specularWidth;

  /// 外轮廓线颜色；null = 不画。
  final Color? contour;

  /// [specular] 的长度：8 个方向 + 回到起点。
  static const int specularStops = 9;

  bool get refracts => refraction > 0 && refractionBand > 0;

  /// 浅色：背景多是白/浅色，高光要亮、轮廓要有一丝暗线才托得住。
  static const GlassOptics light = GlassOptics(
    saturation: 1.8,
    refraction: 10,
    refractionBand: 14,
    rimLight: Color(0x66FFFFFF),
    rimWidth: 6,
    specular: <Color>[
      Color(0x40FFFFFF), // 右
      Color(0x8CFFFFFF), // 右下：反射
      Color(0x1FFFFFFF), // 下
      Color(0x0FFFFFFF), // 左下
      Color(0x59FFFFFF), // 左
      Color(0xE6FFFFFF), // 左上：主光
      Color(0x80FFFFFF), // 上
      Color(0x26FFFFFF), // 右上
      Color(0x40FFFFFF), // 回到右
    ],
    specularWidth: 1.2,
    selectionFill: Color(0x14000000),
    contour: Color(0x14000000),
  );

  /// 深色：高光收着点（暗底上白线很抢眼），轮廓用更深的黑线压边。
  static const GlassOptics dark = GlassOptics(
    saturation: 1.6,
    refraction: 10,
    refractionBand: 14,
    rimLight: Color(0x1FFFFFFF),
    rimWidth: 6,
    specular: <Color>[
      Color(0x1FFFFFFF),
      Color(0x59FFFFFF),
      Color(0x0FFFFFFF),
      Color(0x08FFFFFF),
      Color(0x33FFFFFF),
      Color(0x99FFFFFF),
      Color(0x4DFFFFFF),
      Color(0x14FFFFFF),
      Color(0x1FFFFFFF),
    ],
    specularWidth: 1.2,
    selectionFill: Color(0x24FFFFFF),
    contour: Color(0x52000000),
  );

  /// 饱和度色彩矩阵（`ColorFilter.matrix` 的 4×5 行主序）。
  ///
  /// 亮度权重取 Rec.709（与 sRGB 一致）：s = 1 是单位矩阵，s = 0 是灰度。
  static List<double> saturationMatrix(double s) {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final inv = 1 - s;
    return <double>[
      lr * inv + s, lg * inv, lb * inv, 0, 0, //
      lr * inv, lg * inv + s, lb * inv, 0, 0, //
      lr * inv, lg * inv, lb * inv + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }
}
